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
                r.combinedLikelyExposure += g.likelyExposure;
                r.combinedPipelineExposure += g.pipelineExposure;
                r.probWeightedCompeting += g.probWeightedAmount;
            }
        }
        r.potentialExcess = r.combinedCompeting - r.securedHeadroom;
        r.minimumAdjustmentRequired = r.potentialExcess > 0 ? r.potentialExcess : 0;
        r.severity = severityFor(r.securedHeadroom, r.combinedCompeting, r.probWeightedCompeting);

        enrich(r);   // coverage, concentration, what-can-fit, confidence, coordination, timing

        r.status = CompetingGrantsResult.Status.FOUND;
        return r;
    }

    /** Deterministic Phase-2 analytics: coverage, concentration, scenarios, confidence, etc. */
    private void enrich(CompetingGrantsResult r) {
        r.retrievalTime = System.now();
        r.timingCollisionStatus = 'Full (same fiscal year)';   // scope is one FY; finer period data not in the model

        // Allocation coverage: each opp's total mapped allocation across ALL scopes.
        Set<Id> oppIds = new Set<Id>();
        for (CompetingGrant g : r.grants) { oppIds.add(g.opportunityId); }
        Map<Id, Decimal> totalMappedByOpp = new Map<Id, Decimal>();
        for (Allocation__c a : allocations.byOpportunityIds(oppIds)) {
            if (a.Allocation_Status__c == 'Cancelled') { continue; }
            Opportunity o = opp(a);
            if (o == null) { continue; }
            Decimal cur = totalMappedByOpp.containsKey(o.Id) ? totalMappedByOpp.get(o.Id) : 0;
            totalMappedByOpp.put(o.Id, cur + AmaizeBudgetHeadroom.nz(a.Funds_Allocated__c));
        }

        Set<String> owners = new Set<String>();
        for (CompetingGrant g : r.grants) {
            g.totalMappedAllocation = totalMappedByOpp.containsKey(g.opportunityId)
                ? totalMappedByOpp.get(g.opportunityId) : g.allocatedAmount;
            g.exposureElsewhere = g.totalMappedAllocation - g.allocatedAmount;
            if (g.exposureElsewhere < 0) { g.exposureElsewhere = 0; }
            if (g.opportunityAmount != null && g.opportunityAmount > 0) {
                g.allocationCoveragePct = (g.totalMappedAllocation / g.opportunityAmount * 100).setScale(0);
                Decimal unmapped = g.opportunityAmount - g.totalMappedAllocation;
                g.unmappedAmount = unmapped > 0 ? unmapped : 0;
                r.unmappedOpportunityAmountTotal += g.unmappedAmount;
            }
            if (r.securedHeadroom > 0) {
                g.headroomConsumptionPct = (g.allocatedAmount / r.securedHeadroom * 100).setScale(0);
            }
            if (String.isNotBlank(g.owner)) { owners.add(g.owner); }
        }
        r.distinctOwnerCount = owners.size();

        computeWhatCanFit(r);
        computeConfidence(r);
    }

    /**
     * "What can fit": combinations of competing opportunities whose exposure fits within
     * secured headroom. Enumerate all subsets when few opportunities; otherwise use a small
     * set of useful heuristic scenarios (avoids combinatorial explosion).
     */
    private void computeWhatCanFit(CompetingGrantsResult r) {
        List<CompetingGrant> comp = new List<CompetingGrant>();
        for (CompetingGrant g : r.grants) { if (g.isCompetingPipeline()) { comp.add(g); } }
        if (comp.isEmpty()) { return; }
        Decimal hr = r.securedHeadroom;

        if (comp.size() <= 4) {
            r.exhaustiveCombinations = true;
            Integer n = comp.size();
            for (Integer mask = 1; mask < (1 << n); mask++) {
                List<String> names = new List<String>();
                Decimal exp = 0;
                for (Integer i = 0; i < n; i++) {
                    if ((mask & (1 << i)) != 0) {
                        names.add(shortName(comp[i].opportunityName));
                        exp += (comp[i].likelyExposure + comp[i].pipelineExposure);
                    }
                }
                r.whatCanFit.add(new CompetingGrantsResult.FitScenario(String.join(names, ' + '), exp, hr));
            }
        } else {
            r.exhaustiveCombinations = false;
            // Sort by competing exposure desc for the heuristic scenarios.
            comp.sort(new ByExposureDesc());
            r.whatCanFit.add(new CompetingGrantsResult.FitScenario(
                shortName(comp[0].opportunityName) + ' (largest) only',
                comp[0].likelyExposure + comp[0].pipelineExposure, hr));
            if (comp.size() >= 2) {
                r.whatCanFit.add(new CompetingGrantsResult.FitScenario(
                    'Top two by funding',
                    (comp[0].likelyExposure + comp[0].pipelineExposure)
                        + (comp[1].likelyExposure + comp[1].pipelineExposure), hr));
            }
            r.whatCanFit.add(new CompetingGrantsResult.FitScenario(
                'All likely-stage', r.combinedLikelyExposure, hr));
            r.whatCanFit.add(new CompetingGrantsResult.FitScenario(
                'All competing (' + comp.size() + ')', r.combinedCompeting, hr));
        }
    }

    /** Deterministic Analysis Confidence from data completeness (not LLM-chosen). */
    private void computeConfidence(CompetingGrantsResult r) {
        if (r.noAllocations) {
            r.analysisConfidence = 'Low';
            r.confidenceReasons.add('No funding is recorded against the Budget Lines, so competition cannot be assessed.');
            return;
        }
        String level = 'High';
        // Unmapped opportunity value materially reduces confidence.
        Decimal totalOppAmt = 0, totalUnmapped = 0;
        Boolean anyMissingAmount = false;
        for (CompetingGrant g : r.grants) {
            if (!g.isCompetingPipeline()) { continue; }
            if (g.opportunityAmount != null && g.opportunityAmount > 0) {
                totalOppAmt += g.opportunityAmount;
                totalUnmapped += (g.unmappedAmount == null ? 0 : g.unmappedAmount);
            } else {
                anyMissingAmount = true;
            }
        }
        if (totalOppAmt > 0) {
            Decimal ratio = totalUnmapped / totalOppAmt;
            if (ratio > 0.5) {
                level = 'Low';
                r.confidenceReasons.add(AmaizeFormat.money(totalUnmapped, r.currencyIsoCode)
                    + ' of competing opportunity value is not recorded against Budget Lines, so its funding cannot be fully determined.');
            } else if (ratio > 0.15) {
                level = 'Medium';
                r.confidenceReasons.add(AmaizeFormat.money(totalUnmapped, r.currencyIsoCode)
                    + ' of competing opportunity value is not yet recorded against Budget Lines.');
            }
        }
        if (anyMissingAmount && level == 'High') {
            level = 'Medium';
            r.confidenceReasons.add('Some competing opportunities have no amount, so coverage cannot be computed for them.');
        }
        r.analysisConfidence = level;
    }

    private class ByExposureDesc implements Comparator<CompetingGrant> {
        public Integer compare(CompetingGrant a, CompetingGrant b) {
            Decimal ea = a.likelyExposure + a.pipelineExposure;
            Decimal eb = b.likelyExposure + b.pipelineExposure;
            if (ea == eb) { return 0; }
            return (eb > ea) ? 1 : -1;
        }
    }

    private static String shortName(String name) {
        if (String.isBlank(name)) { return 'Opportunity'; }
        return name.split('[–-]', 2)[0].trim();
    }

    // Cap how many governed scopes an opportunity-start analysis expands into (keeps SOQL bounded).
    private static final Integer MAX_OPP_SCOPES = 5;

    /**
     * Opportunity-start competition: resolve the named grant, find the Budget Lines its
     * allocations touch, determine the governed Headroom scopes those belong to, and run the
     * governed competition for EACH scope (a multi-scope opportunity is analyzed per scope,
     * never collapsed). Grounded in shared Budget Line population, not program text.
     */
    public OpportunityCompetition analyzeForOpportunity(String opportunityName) {
        OpportunityCompetition r = new OpportunityCompetition();
        if (String.isBlank(opportunityName)) {
            r.status = OpportunityCompetition.Status.NEEDS_INFO;
            return r;
        }
        List<Opportunity> hits = matchOpportunities(opportunityName);
        if (hits.isEmpty()) { r.status = OpportunityCompetition.Status.NOT_FOUND; return r; }
        if (hits.size() > 1) {
            r.status = OpportunityCompetition.Status.AMBIGUOUS;
            r.ambiguousChoices = new List<String>();
            for (Opportunity o : hits) { r.ambiguousChoices.add(o.Name); }
            return r;
        }
        Opportunity opp = hits[0];
        r.opportunityId = opp.Id; r.opportunityName = opp.Name; r.accountId = opp.AccountId;
        r.donorName = (opp.Account != null) ? opp.Account.Name : null;
        r.owner = opp.Guardian__c; r.stage = opp.StageName; r.opportunityAmount = opp.Amount;

        List<Allocation__c> allocs = allocations.byOpportunityId(opp.Id);
        Set<Id> blIds = new Set<Id>();
        for (Allocation__c a : allocs) {
            if (a.Allocation_Status__c == 'Cancelled') { continue; }
            if (a.Budget_Line__c != null) { blIds.add(a.Budget_Line__c); }
            if (r.currencyIsoCode == null) { r.currencyIsoCode = a.CurrencyIsoCode; }
        }
        if (blIds.isEmpty()) { r.status = OpportunityCompetition.Status.NO_ALLOCATIONS; return r; }

        Map<Id, Budget_Line__c> blById = new Map<Id, Budget_Line__c>();
        for (Budget_Line__c bl : lines.byIds(blIds)) { blById.put(bl.Id, bl); }
        Map<String, Decimal> exposureByScope = new Map<String, Decimal>();
        Map<String, List<String>> scopeParts = new Map<String, List<String>>();
        for (Allocation__c a : allocs) {
            if (a.Allocation_Status__c == 'Cancelled' || a.Budget_Line__c == null) { continue; }
            Budget_Line__c bl = blById.get(a.Budget_Line__c);
            if (bl == null) { continue; }
            String cat = HeadroomCategoryResolver.categoryForBudgetLine(bl.BusinessUnit__c, bl.Department__c);
            if (cat == null) { continue; }
            String k = cat + '||' + bl.Country__c + '||' + bl.Fiscal_Year__c;
            Decimal cur = exposureByScope.containsKey(k) ? exposureByScope.get(k) : 0;
            exposureByScope.put(k, cur + AmaizeBudgetHeadroom.nz(a.Funds_Allocated__c));
            if (!scopeParts.containsKey(k)) {
                scopeParts.put(k, new List<String>{ cat, bl.Country__c, bl.Fiscal_Year__c });
            }
        }
        r.scopesTouched = exposureByScope.size();
        if (exposureByScope.isEmpty()) { r.status = OpportunityCompetition.Status.NO_ALLOCATIONS; return r; }

        // Largest exposure first; cap the number of governed scopes we expand into.
        List<String> keys = new List<String>(exposureByScope.keySet());
        for (Integer i = 0; i < keys.size(); i++) {
            Integer mx = i;
            for (Integer j = i + 1; j < keys.size(); j++) {
                if (exposureByScope.get(keys[j]) > exposureByScope.get(keys[mx])) { mx = j; }
            }
            if (mx != i) { String t = keys[i]; keys[i] = keys[mx]; keys[mx] = t; }
        }
        Integer limitN = Math.min(keys.size(), MAX_OPP_SCOPES);
        r.capped = keys.size() > limitN;
        for (Integer i = 0; i < limitN; i++) {
            List<String> parts = scopeParts.get(keys[i]);
            CompetingGrantsResult cr = analyze(parts[0], parts[1], parts[2]);
            r.scopes.add(new OpportunityCompetition.ScopeCompetition(
                parts[0], parts[1], parts[2], exposureByScope.get(keys[i]), cr));
        }
        r.status = OpportunityCompetition.Status.FOUND;
        return r;
    }

    /** Match Opportunities by the significant words in a quoted name (excludes Closed Lost). */
    private List<Opportunity> matchOpportunities(String name) {
        List<String> toks = AmaizeMatch.significantTokens(name);
        if (toks.isEmpty()) { return new List<Opportunity>(); }
        List<String> likes = new List<String>();
        Map<String, Object> binds = new Map<String, Object>();
        Integer i = 0;
        for (String t : toks) {
            likes.add('Name LIKE :tok' + i);
            binds.put('tok' + i, '%' + t + '%');
            i++;
        }
        binds.put('lim', 200);
        String soql = 'SELECT Id, Name, Amount, StageName, Probability, CloseDate, Guardian__c, '
            + 'AccountId, Account.Name FROM Opportunity WHERE StageName != \'Closed Lost\' AND '
            + String.join(likes, ' AND ') + ' LIMIT :lim';
        return AmaizeMatch.tokenMatch(name, Database.queryWithBinds(soql, binds, AccessLevel.USER_MODE));
    }

    /**
     * Shared severity rule (also used elsewhere): Critical when already over-allocated on
     * secured funding or the probability-weighted competing pipeline alone would exceed
     * remaining secured headroom; High when all competing close would exceed it; Moderate
     * when it consumes over half; else No Material.
     */
    public static String severityFor(Decimal securedHeadroom, Decimal combinedCompeting, Decimal probWeightedCompeting) {
        if (securedHeadroom < 0) { return 'Critical / Overfunded'; }
        if (combinedCompeting <= 0) { return 'No Material Competition'; }
        if (probWeightedCompeting > securedHeadroom) { return 'Critical / Overfunded'; }
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
