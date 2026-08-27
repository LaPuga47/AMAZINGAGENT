/**
 * CompetingGrantsPhase2Test — the Phase-2 decision-useful analytics: deterministic
 * Analysis Confidence, allocation coverage / unmapped, headroom concentration, what-can-fit
 * scenarios, minimum adjustment, distinct owners, and the large-population heuristic.
 *
 * Uses an isolated Systems Change - KE budget line (budget only). Funding fields roll up from
 * allocations, so secured headroom = budget when only Likely/Pipeline allocations are added.
 */
@isTest
private class CompetingGrantsPhase2Test {

    private static final String CAT = 'System Change';   // -> Systems Change base
    private static final String BU = 'Systems Change - KE';

    @TestSetup
    static void setup() {
        Budget_Scenario__c s = HeadroomTestData.makeCurrentScenario();
        HeadroomTestData.makeLine(s.Id, 'Kenya', BU, 'N/A', 'N/A', 'N/A', 'N/A', -2000000, 0, 0, 0);
    }

    private static Id lineId() {
        return [SELECT Id FROM Budget_Line__c WHERE BusinessUnit__c = :BU LIMIT 1].Id;
    }
    private static CompetingGrantsResult run() {
        return new CompetingGrantsService().analyze(CAT, 'Kenya', '2027');
    }

    @isTest
    static void confidenceHighWhenFullyMapped() {
        // Opp amount 300k, allocated 300k -> 0 unmapped -> High. Secured HR = 2.0M (no secured alloc).
        HeadroomTestData.makeOppAllocations('Pipeline', new List<Id>{ lineId() }, 300000, 'Kenya', BU, 300000, 'RM A');
        Test.startTest();
        CompetingGrantsResult c = run();
        Test.stopTest();
        System.assertEquals('High', c.analysisConfidence, c.confidenceReasons.toString());
        System.assertEquals(2000000, c.securedHeadroom);
    }

    @isTest
    static void confidenceMediumWhenPartiallyUnmapped() {
        HeadroomTestData.makeOppAllocations('Pipeline', new List<Id>{ lineId() }, 400000, 'Kenya', BU, 500000, 'RM A');
        Test.startTest();
        CompetingGrantsResult c = run();
        Test.stopTest();
        System.assertEquals('Medium', c.analysisConfidence, c.confidenceReasons.toString());
    }

    @isTest
    static void confidenceLowWhenLargelyUnmapped() {
        HeadroomTestData.makeOppAllocations('Pipeline', new List<Id>{ lineId() }, 300000, 'Kenya', BU, 1000000, 'RM A');
        Test.startTest();
        CompetingGrantsResult c = run();
        Test.stopTest();
        System.assertEquals('Low', c.analysisConfidence, c.confidenceReasons.toString());
    }

    @isTest
    static void coverageAndConcentrationComputed() {
        HeadroomTestData.makeOppAllocations('Pipeline', new List<Id>{ lineId() }, 500000, 'Kenya', BU, 1000000, 'RM A');
        Test.startTest();
        CompetingGrantsResult c = run();
        Test.stopTest();
        CompetingGrant g = c.grants[0];
        System.assertEquals(50, g.allocationCoveragePct, 'mapped 500k of 1.0M');
        System.assertEquals(500000, g.unmappedAmount);
        System.assertEquals(25, g.headroomConsumptionPct, '500k of 2.0M secured headroom');
    }

    @isTest
    static void whatCanFitAndMinimumAdjustment() {
        // Two pipeline opps 1.2M + 1.0M = 2.2M competing vs 2.0M headroom -> excess 200k.
        HeadroomTestData.makeAllocations(new List<HeadroomTestData.AllocSpec>{
            new HeadroomTestData.AllocSpec('Pipeline', 1200000),
            new HeadroomTestData.AllocSpec('Pipeline', 1000000)
        }, lineId(), 'Kenya', BU);
        Test.startTest();
        CompetingGrantsResult c = run();
        Test.stopTest();
        System.assertEquals(2200000, c.combinedCompeting);
        System.assertEquals(200000, c.minimumAdjustmentRequired);
        System.assert(c.exhaustiveCombinations, 'few opportunities -> exhaustive combinations');
        Boolean sawExceeds = false, sawFits = false;
        for (CompetingGrantsResult.FitScenario f : c.whatCanFit) {
            if (!f.fits && f.excess == 200000) { sawExceeds = true; }
            if (f.fits) { sawFits = true; }
        }
        System.assert(sawExceeds, 'the both-close scenario exceeds by 200k');
        System.assert(sawFits, 'each alone fits');
    }

    @isTest
    static void distinctOwnersCounted() {
        HeadroomTestData.makeOppAllocations('Pipeline', new List<Id>{ lineId() }, 300000, 'Kenya', BU, null, 'RM A');
        HeadroomTestData.makeOppAllocations('Pipeline', new List<Id>{ lineId() }, 300000, 'Kenya', BU, null, 'RM B');
        Test.startTest();
        CompetingGrantsResult c = run();
        Test.stopTest();
        System.assertEquals(2, c.grants.size());
        System.assertEquals(2, c.distinctOwnerCount);
    }

    @isTest
    static void largePopulationUsesHeuristicScenarios() {
        HeadroomTestData.makeAllocations(new List<HeadroomTestData.AllocSpec>{
            new HeadroomTestData.AllocSpec('Pipeline', 100000),
            new HeadroomTestData.AllocSpec('Pipeline', 100000),
            new HeadroomTestData.AllocSpec('Pipeline', 100000),
            new HeadroomTestData.AllocSpec('Pipeline', 100000),
            new HeadroomTestData.AllocSpec('Pipeline', 100000)
        }, lineId(), 'Kenya', BU);
        Test.startTest();
        CompetingGrantsResult c = run();
        Test.stopTest();
        System.assertEquals(5, c.grants.size());
        System.assertEquals(false, c.exhaustiveCombinations, '>4 competing -> heuristic scenarios only');
        System.assert(!c.whatCanFit.isEmpty(), 'heuristic scenarios still produced');
    }
}
