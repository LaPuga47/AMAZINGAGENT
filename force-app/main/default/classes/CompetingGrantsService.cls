/**
 * CompetingGrantsService — finds the grant Opportunities competing for the SAME funding
 * scope and quantifies the competition against the scope's headroom.
 *
 * It reuses the Budget-Line-first engine: the scope is resolved to the matching current-
 * scenario Budget Lines (with the same business-unit suffix tolerance as headroom
 * analysis), and competition is measured at the allocation-to-Budget-Line grain — which is
 * what prevents false competition (two grants on the same program but different lines) and
 * double-counting (an Opportunity's allocated amount, not its raw Amount).
 *
 * Funding certainty comes from Allocation_Type__c (Secured/Likely/Pipeline): Secured/
 * Released is treated as already consuming headroom; Likely/Pipeline is the competing
 * pipeline. Headroom figures are read from the Budget Lines' own stored/calculated fields,
 * so they never disagree with the org formulas. Read-only: no DML.
 */
public with sharing class CompetingGrantsService {

    private final IBudgetLineSelector lines;
    private final IAllocationSelector allocations;

    public CompetingGrantsService() {
        this(new BudgetLineSelector(), new AllocationSelector());
    }

    public CompetingGrantsService(IBudgetLineSelector lines, IAllocationSelector allocations) {
        this.lines = lines;
        this.allocations = allocations;
    }

    public CompetingGrantsResult analyze(BudgetLineDimensions raw) {
        CompetingGrantsResult r = new CompetingGrantsResult();
        BudgetLineDimensions d = (raw == null ? new BudgetLineDimensions() : raw).normalize();
        r.requested = d;

        // Minimum scope: fiscal year + country + business unit (same as headroom analysis).
        if (!d.hasRequiredMinimum()) {
            r.status = CompetingGrantsResult.Status.NEEDS_INFO;
            r.missingDimensions = d.missingRequired();
            return r;
        }

        // Resolve the scope to its current-scenario Budget Lines (may be several — the
        // "program envelope" the RM is asking about).
        List<Budget_Line__c> scope = lines.findByDimensions(d);
        if (scope == null || scope.isEmpty()) {
            r.status = CompetingGrantsResult.Status.NOT_FOUND;
            return r;
        }

        summariseScope(r, scope, d);
        Map<Id, CompetingGrant> byOpp = gatherGrants(scope);
        r.grants = rankGrants(byOpp.values());
        computeExposure(r);
        r.severity = classify(r);
        r.status = CompetingGrantsResult.Status.FOUND;
        return r;
    }

    /**
     * Roll the matched Budget Lines' stored figures into one scope-level picture. Budget and
     * SECURED headroom come from the stored/calculated fields (consistent with Headroom
     * Analysis; secured funding rolls up reliably). Likely/pipeline funding and the forecast
     * headroom are derived from the allocations this service actually reads (see
     * computeExposure) rather than the stored rollup, so they also capture allocations that
     * resolve only through the Match Key and are always self-consistent with the grants shown.
     */
    private void summariseScope(CompetingGrantsResult r, List<Budget_Line__c> scope, BudgetLineDimensions d) {
        r.country = d.country;
        r.businessUnit = d.businessUnit;
        r.fiscalYear = d.fiscalYear;
        r.lineCount = scope.size();
        for (Budget_Line__c bl : scope) {
            r.budgetCost += AmaizeBudgetHeadroom.budgetCost(bl.Budget_Amount__c);
            r.securedFunding += AmaizeBudgetHeadroom.nz(bl.Secured_Funding__c);
            r.securedHeadroom += AmaizeBudgetHeadroom.nz(bl.Secured_Headroom__c);
            if (r.currencyIsoCode == null) { r.currencyIsoCode = bl.CurrencyIsoCode; }
        }
    }

    /** Gather allocations for the scope (direct link + unlinked Match Key) grouped by Opportunity. */
    private Map<Id, CompetingGrant> gatherGrants(List<Budget_Line__c> scope) {
        Set<Id> lineIds = new Set<Id>();
        Set<String> keys = new Set<String>();
        for (Budget_Line__c bl : scope) {
            lineIds.add(bl.Id);
            if (String.isNotBlank(bl.Budget_Line_Unique_Key__c)) { keys.add(bl.Budget_Line_Unique_Key__c); }
        }
        List<Allocation__c> allocs = allocations.byBudgetLineIds(lineIds);
        allocs.addAll(allocations.byMatchKeysUnlinked(keys));

        Map<Id, CompetingGrant> byOpp = new Map<Id, CompetingGrant>();
        for (Allocation__c a : allocs) {
            Opportunity o = opp(a);
            if (o == null) { continue; }
            // Closed Lost grants are not demand.
            if (o.StageName == 'Closed Lost') { continue; }
            String type = a.Allocation_Type__c;
            String stat = a.Allocation_Status__c;
            if (stat == 'Cancelled') { continue; }  // cancelled allocations don't compete

            CompetingGrant g = byOpp.get(o.Id);
            if (g == null) {
                g = new CompetingGrant();
                g.opportunityId = o.Id;
                g.opportunityName = o.Name;
                g.donor = (o.Account != null) ? o.Account.Name : null;
                g.owner = o.Guardian__c;
                g.stage = o.StageName;
                g.probability = o.Probability;
                g.closeDate = o.CloseDate;
                g.currencyIsoCode = a.CurrencyIsoCode;
                byOpp.put(o.Id, g);
            }
            g.allocatedAmount += AmaizeBudgetHeadroom.nz(a.Funds_Allocated__c);
            g.probWeightedAmount += AmaizeBudgetHeadroom.nz(a.Prob_Weighted_Allocation_Amount__c);
            if (type == 'Secured') { g.hasSecured = true; }
            if (type == 'Likely') { g.hasLikely = true; }
            if (type == 'Pipeline') { g.hasPipeline = true; }
            if (stat == 'Approved' || stat == 'Released') { g.hasApproved = true; }
            if (stat == 'Approved' || stat == 'Released' || type == 'Secured' || type == 'Likely' || type == 'Pipeline') {
                // any real (non Draft/Suggested) signal clears the "unconfirmed only" flag
                if (stat == 'Approved' || stat == 'Released') { g.onlyUnconfirmed = false; }
            }
        }
        return byOpp;
    }

    /** Competing pipeline first, then most advanced (probability desc, then earliest close). */
    private List<CompetingGrant> rankGrants(List<CompetingGrant> grants) {
        List<CompetingGrant> out = new List<CompetingGrant>(grants);
        out.sort(new ByAdvancementDesc());
        return out;
    }

    /**
     * Exposure: combined competing pipeline vs the scope's remaining secured headroom.
     * Likely/pipeline funding and forecast headroom are derived here from the allocations
     * this service read, so they stay consistent with the grants shown (and include
     * Match-Key-resolved allocations the stored rollup may not yet reflect).
     */
    private void computeExposure(CompetingGrantsResult r) {
        for (CompetingGrant g : r.grants) {
            if (g.hasSecured) {
                // secured portion already reflected in stored securedHeadroom; not competing
            }
            if (g.isCompetingPipeline()) {
                r.combinedCompeting += g.allocatedAmount;
                r.probWeightedCompeting += g.probWeightedAmount;
                if (g.hasLikely) { r.likelyFunding += g.allocatedAmount; }
                else if (g.hasPipeline) { r.pipelineFunding += g.allocatedAmount; }
            }
        }
        r.potentialExcess = r.combinedCompeting - r.securedHeadroom;
        // Effective forecast headroom = secured headroom minus the competing pipeline.
        r.forecastHeadroom = r.securedHeadroom - r.combinedCompeting;
    }

    /**
     * Severity — weighs more than one number, and uses the reliably-rolled-up SECURED
     * headroom rather than the (partial) stored forecast rollup:
     *   Critical  — already over-allocated on secured funding alone (securedHeadroom < 0),
     *               or the probability-weighted competing pipeline alone would exceed it.
     *   High      — if ALL competing grants close, combined pipeline would exceed headroom.
     *   Moderate  — combined pipeline would consume more than half the remaining headroom.
     *   None      — headroom comfortably exceeds the competing pipeline.
     */
    private String classify(CompetingGrantsResult r) {
        if (r.securedHeadroom < 0) { return 'Critical / Over-allocated'; }
        if (r.combinedCompeting <= 0) { return 'No Material Competition'; }
        if (r.probWeightedCompeting > r.securedHeadroom) { return 'Critical / Over-allocated'; }
        if (r.combinedCompeting > r.securedHeadroom) { return 'High Competition'; }
        if (r.combinedCompeting > r.securedHeadroom / 2) { return 'Moderate Competition'; }
        return 'No Material Competition';
    }

    private static Opportunity opp(Allocation__c a) {
        if (a.Restriction__r != null && a.Restriction__r.Gift_Commitment__r != null) {
            return a.Restriction__r.Gift_Commitment__r.Opportunity;
        }
        return null;
    }

    /** Competing pipeline first; within that, higher probability first, then earlier close. */
    private class ByAdvancementDesc implements Comparator<CompetingGrant> {
        public Integer compare(CompetingGrant a, CompetingGrant b) {
            if (a.isCompetingPipeline() != b.isCompetingPipeline()) {
                return a.isCompetingPipeline() ? -1 : 1;
            }
            Decimal pa = a.probability == null ? -1 : a.probability;
            Decimal pb = b.probability == null ? -1 : b.probability;
            if (pa != pb) { return (pb > pa) ? 1 : -1; }
            if (a.closeDate == b.closeDate) { return 0; }
            if (a.closeDate == null) { return 1; }
            if (b.closeDate == null) { return -1; }
            return (a.closeDate < b.closeDate) ? -1 : 1;
        }
    }
}
