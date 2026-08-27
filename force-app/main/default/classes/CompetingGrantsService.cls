/**
 * CompetingGrantsService — governed competing-grants analysis. It resolves the SAME governed
 * Budget Line population that Headroom Analysis uses (via HeadroomCategoryResolver +
 * BudgetLineSelector.findByGovernedScope) for a Country + Fiscal Year + Headroom Category,
 * aggregates the governed financial fields across ALL qualifying lines, then retrieves the
 * Funding Allocations across that whole population and groups them by Opportunity as
 * allocation EXPOSURE (never the Opportunity Amount).
 *
 * Headroom totals here are identical to Headroom Analysis for the same scope by construction:
 * both sum the same stored Budget Line fields over the same qualifying records. Read-only.
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

    /** Governed competing-grants analysis for a category / country / fiscal year. */
    public CompetingGrantsResult analyze(String program, String country, String fiscalYear) {
        CompetingGrantsResult r = new CompetingGrantsResult();
        String cat = program == null ? '' : program.trim();
        String ctry = country == null ? '' : country.trim();
        if (cat == '') { r.missing.add('headroom category'); }
        if (ctry == '') { r.missing.add('country'); }
        if (!r.missing.isEmpty()) { r.status = CompetingGrantsResult.Status.NEEDS_INFO; return r; }

        HeadroomCategoryResolver.Rule rule = HeadroomCategoryResolver.resolve(cat);
        r.category = rule.label;
        r.country = ctry;
        if (rule.mode == HeadroomCategoryResolver.Mode.ZERO) {
            r.status = CompetingGrantsResult.Status.ZERO;
            r.headroomStatus = 'Not Applicable';
            return r;
        }
        if (rule.mode == HeadroomCategoryResolver.Mode.NOT_CONFIGURED) {
            r.status = CompetingGrantsResult.Status.NOT_CONFIGURED;
            return r;
        }

        Budget_Scenario__c scenario = currentScenario();
        String fy = String.isNotBlank(fiscalYear) ? fiscalYear.trim()
                    : (scenario != null ? scenario.Fiscal_Year__c : null);
        r.fiscalYear = fy;
        r.scenarioLabel = scenarioLabel(scenario);

        // Resolve the COMPLETE governed Budget Line population (same filters as Headroom Analysis).
        BudgetLineDimensions d = new BudgetLineDimensions();
        d.country = ctry; d.fiscalYear = fy;
        d.businessUnit = rule.businessUnitBase; d.department = rule.department;
        d = d.normalize();
        List<Budget_Line__c> scope = lines.findByGovernedScope(d);
        if (scope.isEmpty()) {
            r.status = CompetingGrantsResult.Status.NONE;
            return r;
        }

        // Aggregate the governed totals across the qualifying lines (stored fields, summed).
        Set<Id> lineIds = new Set<Id>();
        Set<String> keys = new Set<String>();
        for (Budget_Line__c bl : scope) {
            lineIds.add(bl.Id);
            if (String.isNotBlank(bl.Budget_Line_Unique_Key__c)) { keys.add(bl.Budget_Line_Unique_Key__c); }
            r.budgetAmount += AmaizeBudgetHeadroom.budgetCost(bl.Budget_Amount__c);
            r.securedFunding += AmaizeBudgetHeadroom.nz(bl.Secured_Funding__c);
            r.likelyFunding += AmaizeBudgetHeadroom.nz(bl.Likely_Funding__c);
            r.pipelineFunding += AmaizeBudgetHeadroom.nz(bl.Pipeline_Funding__c);
            r.forecastFunding += AmaizeBudgetHeadroom.nz(bl.Forecast_Funding__c);
            r.securedHeadroom += AmaizeBudgetHeadroom.nz(bl.Secured_Headroom__c);
            r.forecastHeadroom += AmaizeBudgetHeadroom.nz(bl.Forecast_Headroom__c);
            if (r.currencyIsoCode == null) { r.currencyIsoCode = bl.CurrencyIsoCode; }
        }
        r.budgetLineCount = scope.size();
        r.headroomStatus = AmaizeBudgetHeadroom.statusFor(r.securedHeadroom);

        // Retrieve allocations across the WHOLE population (direct link + unlinked Match Key), dedupe.
        Map<Id, Allocation__c> allocById = new Map<Id, Allocation__c>();
        for (Allocation__c a : allocations.byBudgetLineIds(lineIds)) { allocById.put(a.Id, a); }
        for (Allocation__c a : allocations.byMatchKeysUnlinked(keys)) {
            if (!allocById.containsKey(a.Id)) { allocById.put(a.Id, a); }
        }
        if (allocById.isEmpty()) { r.noAllocations = true; }

        // Group by Opportunity, summing allocation EXPOSURE (dedupe grants by Opportunity Id).
        Map<Id, CompetingGrant> byOpp = new Map<Id, CompetingGrant>();
        for (Allocation__c a : allocById.values()) {
            if (a.Allocation_Status__c == 'Cancelled') { continue; }
            Opportunity o = opp(a);
            if (o == null || o.StageName == 'Closed Lost') { continue; }
            CompetingGrant g = byOpp.get(o.Id);
            if (g == null) {
                g = new CompetingGrant();
                g.opportunityId = o.Id; g.opportunityName = o.Name;
                g.accountId = o.AccountId; g.donorName = (o.Account != null) ? o.Account.Name : null;
                g.owner = o.Guardian__c; g.stage = o.StageName; g.probability = o.Probability;
                g.closeDate = o.CloseDate; g.opportunityAmount = o.Amount; g.currencyIsoCode = a.CurrencyIsoCode;
                byOpp.put(o.Id, g);
            }
            g.addAllocation(a, AmaizeBudgetHeadroom.nz(a.Funds_Allocated__c),
                            AmaizeBudgetHeadroom.nz(a.Prob_Weighted_Allocation_Amount__c));
            if (a.Restriction__r == null || a.Restriction__r.Gift_Commitment__r == null) {
                r.allocationsMissingGiftCommitment++;
            }
        }
        r.grants = new List<CompetingGrant>(byOpp.values());
        r.grants.sort(new ByAdvancementDesc());

        for (CompetingGrant g : r.grants) {
            if (g.isCompetingPipeline()) {
                r.combinedCompeting += (g.likelyExposure + g.pipelineExposure);
                r.probWeightedCompeting += g.probWeightedAmount;
            }
        }
        r.potentialExcess = r.combinedCompeting - r.securedHeadroom;
        r.severity = severityFor(r.securedHeadroom, r.combinedCompeting, r.probWeightedCompeting);
        r.status = CompetingGrantsResult.Status.FOUND;
        return r;
    }

    /**
     * Shared severity rule (also used elsewhere): Critical when already over-allocated on
     * secured funding or the probability-weighted competing pipeline alone would exceed
     * remaining secured headroom; High when all competing close would exceed it; Moderate
     * when it consumes over half; else No Material.
     */
    public static String severityFor(Decimal securedHeadroom, Decimal combinedCompeting, Decimal probWeightedCompeting) {
        if (securedHeadroom < 0) { return 'Critical / Over-allocated'; }
        if (combinedCompeting <= 0) { return 'No Material Competition'; }
        if (probWeightedCompeting > securedHeadroom) { return 'Critical / Over-allocated'; }
        if (combinedCompeting > securedHeadroom) { return 'High Competition'; }
        if (combinedCompeting > securedHeadroom / 2) { return 'Moderate Competition'; }
        return 'No Material Competition';
    }

    private Budget_Scenario__c currentScenario() {
        List<Budget_Scenario__c> s = [
            SELECT Id, Fiscal_Year__c, Scenario_Type__c FROM Budget_Scenario__c
            WHERE Is_Current_Scenario__c = true WITH USER_MODE LIMIT 1];
        return s.isEmpty() ? null : s[0];
    }

    private String scenarioLabel(Budget_Scenario__c s) {
        if (s == null) { return null; }
        return (s.Scenario_Type__c != null ? s.Scenario_Type__c + ' ' : '')
            + (s.Fiscal_Year__c != null ? 'FY' + s.Fiscal_Year__c : '');
    }

    private static Opportunity opp(Allocation__c a) {
        if (a.Restriction__r != null && a.Restriction__r.Gift_Commitment__r != null) {
            return a.Restriction__r.Gift_Commitment__r.Opportunity;
        }
        return null;
    }

    /** Competing pipeline first; then higher probability, then earlier close date. */
    private class ByAdvancementDesc implements Comparator<CompetingGrant> {
        public Integer compare(CompetingGrant a, CompetingGrant b) {
            if (a.isCompetingPipeline() != b.isCompetingPipeline()) { return a.isCompetingPipeline() ? -1 : 1; }
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
