/**
 * FundingContextService — the relationship-aware funding navigator behind the Competing
 * Grants Analysis sub-agent. It assembles the funding graph around a starting record and
 * supports bidirectional navigation:
 *
 *   - Budget-Line direction (backward lineage): given a scope (country + business unit,
 *     optionally narrowed), return the Budget Lines and the allocations consuming them,
 *     each with its Restriction -> Gift Commitment -> Opportunity -> donor lineage, plus
 *     headroom and competing-grants analysis.
 *   - Opportunity direction (forward lineage): given a grant name, return the Budget Lines
 *     its funding is allocated against (via Restriction -> Gift Commitment -> Opportunity),
 *     with allocation amounts and scenarios.
 *
 * It reuses the deployed engine (BudgetLineSelector, AllocationSelector, AmaizeBudgetHeadroom,
 * CompetingGrantsService.severityFor) and the org's approved relationships — Allocation is
 * the anchor (there is no direct Opportunity/Gift Commitment lookup on Allocation, so the
 * grant lineage is traversed through Restriction). It never infers a relationship from
 * matching field values; unresolved links are reported, not fabricated. Read-only: no DML.
 */
public with sharing class FundingContextService {

    private final IBudgetLineSelector lines;
    private final IAllocationSelector allocations;

    public FundingContextService() {
        this(new BudgetLineSelector(), new AllocationSelector());
    }
    public FundingContextService(IBudgetLineSelector lines, IAllocationSelector allocations) {
        this.lines = lines;
        this.allocations = allocations;
    }

    /* ---------------- Budget-Line direction (what funds this scope) ---------------- */

    public FundingContext forBudgetLineScope(BudgetLineDimensions raw) {
        FundingContext fc = new FundingContext();
        fc.direction = 'budget-line';
        BudgetLineDimensions d = (raw == null ? new BudgetLineDimensions() : raw).normalize();
        fc.requested = d;

        if (!d.hasRequiredMinimum()) {
            fc.status = FundingContext.Status.NEEDS_INFO;
            fc.missingDimensions = d.missingRequired();
            return fc;
        }
        List<Budget_Line__c> scope = lines.findByDimensions(d);
        if (scope == null || scope.isEmpty()) {
            fc.status = FundingContext.Status.NOT_FOUND;
            return fc;
        }

        fc.country = d.country; fc.businessUnit = d.businessUnit; fc.fiscalYear = d.fiscalYear;
        fc.budgetLines = scope;

        Set<Id> lineIds = new Set<Id>();
        Set<String> keys = new Set<String>();
        for (Budget_Line__c bl : scope) {
            lineIds.add(bl.Id);
            if (String.isNotBlank(bl.Budget_Line_Unique_Key__c)) { keys.add(bl.Budget_Line_Unique_Key__c); }
            fc.budgetCost += AmaizeBudgetHeadroom.budgetCost(bl.Budget_Amount__c);
            fc.securedFunding += AmaizeBudgetHeadroom.nz(bl.Secured_Funding__c);
            fc.securedHeadroom += AmaizeBudgetHeadroom.nz(bl.Secured_Headroom__c);
            if (fc.currencyIsoCode == null) { fc.currencyIsoCode = bl.CurrencyIsoCode; }
        }

        List<Allocation__c> direct = allocations.byBudgetLineIds(lineIds);
        List<Allocation__c> viaKey = allocations.byMatchKeysUnlinked(keys);
        fc.viaMatchKey = !viaKey.isEmpty();
        List<Allocation__c> all = new List<Allocation__c>(direct);
        all.addAll(viaKey);
        fc.allocations = dedupeAllocations(all);

        analyseGraph(fc);
        fc.severity = CompetingGrantsService.severityFor(fc.securedHeadroom, fc.combinedCompeting, fc.probWeightedCompeting);
        fc.status = FundingContext.Status.FOUND_BUDGET_LINE;
        return fc;
    }

    /* ---------------- Opportunity direction (where this grant is allocated) ---------------- */

    public FundingContext forOpportunity(String opportunityName) {
        FundingContext fc = new FundingContext();
        fc.direction = 'opportunity';

        if (String.isBlank(opportunityName)) {
            fc.status = FundingContext.Status.NEEDS_INFO;
            fc.missingDimensions = new List<String>{ 'grant (opportunity) name' };
            return fc;
        }
        List<Opportunity> hits = matchOpportunities(opportunityName);
        if (hits.isEmpty()) {
            fc.status = FundingContext.Status.NOT_FOUND;
            return fc;
        }
        if (hits.size() > 1) {
            fc.status = FundingContext.Status.AMBIGUOUS;
            fc.ambiguousChoices = new List<String>();
            for (Opportunity o : hits) { fc.ambiguousChoices.add(o.Name); }
            return fc;
        }

        Opportunity opp = hits[0];
        fc.focusOpportunity = opp;
        fc.allocations = dedupeAllocations(allocations.byOpportunityId(opp.Id));

        // Resolve the Budget Lines those allocations point to (direct link only; unlinked
        // allocations are reported as not directly tied to a Budget Line).
        Set<Id> lineIds = new Set<Id>();
        for (Allocation__c a : fc.allocations) {
            if (a.Budget_Line__c != null) { lineIds.add(a.Budget_Line__c); }
            else { fc.allocationsUnlinkedToBudgetLine++; }
        }
        fc.budgetLines = lines.byIds(lineIds);
        for (Allocation__c a : fc.allocations) {
            if (fc.currencyIsoCode == null) { fc.currencyIsoCode = a.CurrencyIsoCode; }
        }
        countDataQuality(fc);
        fc.status = FundingContext.Status.FOUND_OPPORTUNITY;
        return fc;
    }

    /* ---------------- shared helpers ---------------- */

    /** Sum competing exposure and tally lineage data-quality gaps across the allocations. */
    private void analyseGraph(FundingContext fc) {
        for (Allocation__c a : fc.allocations) {
            String type = a.Allocation_Type__c;
            if ((type == 'Likely' || type == 'Pipeline') && a.Allocation_Status__c != 'Cancelled') {
                fc.combinedCompeting += AmaizeBudgetHeadroom.nz(a.Funds_Allocated__c);
                fc.probWeightedCompeting += AmaizeBudgetHeadroom.nz(a.Prob_Weighted_Allocation_Amount__c);
            }
        }
        fc.potentialExcess = fc.combinedCompeting - fc.securedHeadroom;
        countDataQuality(fc);
    }

    private void countDataQuality(FundingContext fc) {
        for (Allocation__c a : fc.allocations) {
            if (a.Restriction__c == null || a.Restriction__r == null) { fc.allocationsMissingRestriction++; continue; }
            if (a.Restriction__r.Gift_Commitment__r == null) { fc.allocationsMissingGiftCommitment++; }
        }
    }

    /** Dedupe allocations by record Id (the same allocation can arrive via two queries). */
    private List<Allocation__c> dedupeAllocations(List<Allocation__c> allocs) {
        Map<Id, Allocation__c> byId = new Map<Id, Allocation__c>();
        for (Allocation__c a : allocs) {
            if (!byId.containsKey(a.Id)) { byId.put(a.Id, a); }
        }
        return byId.values();
    }

    /**
     * Match Opportunities by the significant words in the quoted name (same token approach
     * AmaizeGetOpportunityContext uses), excluding Closed Lost. Returns 0, 1, or several.
     */
    private List<Opportunity> matchOpportunities(String name) {
        List<String> toks = AmaizeMatch.significantTokens(name);
        if (toks.isEmpty()) { return new List<Opportunity>(); }
        List<String> likes = new List<String>();
        Map<String, Object> binds = new Map<String, Object>();
        Integer i = 0;
        for (String t : toks) {
            String key = 'tok' + i;
            likes.add('Name LIKE :' + key);
            binds.put(key, '%' + t + '%');
            i++;
        }
        binds.put('lim', 200);
        String soql = 'SELECT Id, Name, Amount, StageName, Probability, CloseDate, Guardian__c, Account.Name '
            + 'FROM Opportunity WHERE StageName != \'Closed Lost\' AND ' + String.join(likes, ' AND ')
            + ' LIMIT :lim';
        List<Opportunity> candidates = Database.queryWithBinds(soql, binds, AccessLevel.USER_MODE);
        return AmaizeMatch.tokenMatch(name, candidates);
    }
}
