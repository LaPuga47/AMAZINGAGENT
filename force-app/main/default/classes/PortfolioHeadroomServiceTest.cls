/**
 * PortfolioHeadroomServiceTest — portfolio ranking across governed scopes: collision risk,
 * tightest headroom, most competition, category filter, and topN. Two scopes with known
 * headroom + competing exposure make the ordering deterministic.
 *
 * Budget lines carry budget only; competing (Pipeline) allocations roll up their funding, and
 * secured headroom stays at the full budget (no secured allocations).
 */
@isTest
private class PortfolioHeadroomServiceTest {

    @TestSetup
    static void setup() {
        Budget_Scenario__c s = HeadroomTestData.makeCurrentScenario();
        // Kenya Core Program: 5.0M budget.  Rwanda Core Program: 2.0M budget.
        HeadroomTestData.makeLine(s.Id, 'Kenya', 'Core Program - KE', 'N/A', 'N/A', 'N/A', 'N/A', -5000000, 0, 0, 0);
        HeadroomTestData.makeLine(s.Id, 'Rwanda', 'Core Program - RW', 'N/A', 'N/A', 'N/A', 'N/A', -2000000, 0, 0, 0);
    }

    private static Id lineId(String bu) {
        return [SELECT Id FROM Budget_Line__c WHERE BusinessUnit__c = :bu LIMIT 1].Id;
    }

    static void seedCompetition() {
        // Rwanda competing 2.5M (> 2.0M headroom -> 0.5M excess); Kenya competing 2.8M (< 5.0M -> spare).
        HeadroomTestData.makeAllocations(new List<HeadroomTestData.AllocSpec>{
            new HeadroomTestData.AllocSpec('Pipeline', 1500000),
            new HeadroomTestData.AllocSpec('Pipeline', 1000000)
        }, lineId('Core Program - RW'), 'Rwanda', 'Core Program - RW');
        HeadroomTestData.makeAllocations(new List<HeadroomTestData.AllocSpec>{
            new HeadroomTestData.AllocSpec('Pipeline', 2800000)
        }, lineId('Core Program - KE'), 'Kenya', 'Core Program - KE');
    }

    @isTest
    static void ranksByCollisionRisk() {
        seedCompetition();
        Test.startTest();
        List<PortfolioScopeRisk> ranked = new PortfolioHeadroomService().rank('collision', null, null, '2027', 10);
        Test.stopTest();
        System.assertEquals(2, ranked.size());
        System.assertEquals('Rwanda', ranked[0].country, 'Rwanda has the over-allocation');
        System.assertEquals(500000, ranked[0].minimumAdjustmentRequired);
        System.assertEquals(0, ranked[1].minimumAdjustmentRequired, 'Kenya fits');
    }

    @isTest
    static void ranksByTightestHeadroom() {
        seedCompetition();
        Test.startTest();
        List<PortfolioScopeRisk> ranked = new PortfolioHeadroomService().rank('tightest headroom', null, null, '2027', 10);
        Test.stopTest();
        System.assertEquals('Rwanda', ranked[0].country, 'Rwanda 2.0M < Kenya 5.0M');
        System.assertEquals(2000000, ranked[0].securedHeadroom);
    }

    @isTest
    static void ranksByMostCompetition() {
        seedCompetition();
        Test.startTest();
        List<PortfolioScopeRisk> ranked = new PortfolioHeadroomService().rank('most competition', null, null, '2027', 10);
        Test.stopTest();
        System.assertEquals('Kenya', ranked[0].country, 'Kenya 2.8M > Rwanda 2.5M competing');
        System.assertEquals(2800000, ranked[0].combinedCompeting);
    }

    @isTest
    static void countryFilterLimitsScopes() {
        seedCompetition();
        Test.startTest();
        List<PortfolioScopeRisk> ranked = new PortfolioHeadroomService().rank('collision', null, 'Rwanda', '2027', 10);
        Test.stopTest();
        System.assertEquals(1, ranked.size());
        System.assertEquals('Rwanda', ranked[0].country);
    }

    @isTest
    static void topNCapsResults() {
        seedCompetition();
        Test.startTest();
        List<PortfolioScopeRisk> ranked = new PortfolioHeadroomService().rank('collision', null, null, '2027', 1);
        Test.stopTest();
        System.assertEquals(1, ranked.size(), 'topN=1 returns only the highest-risk scope');
        System.assertEquals('Rwanda', ranked[0].country);
    }

    @isTest
    static void scopeWithNoCompetitionStillListed() {
        // No allocations at all -> scopes still appear with zero competing exposure.
        Test.startTest();
        List<PortfolioScopeRisk> ranked = new PortfolioHeadroomService().rank('tightest headroom', null, null, '2027', 10);
        Test.stopTest();
        System.assertEquals(2, ranked.size());
        System.assertEquals(0, ranked[0].combinedCompeting);
    }
}
