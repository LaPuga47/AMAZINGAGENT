/**
 * AmaizePortfolioRisksTest — the portfolio action: ranked summary, match count, and the
 * read-only guardrail.
 */
@isTest
private class AmaizePortfolioRisksTest {

    @TestSetup
    static void setup() {
        Budget_Scenario__c s = HeadroomTestData.makeCurrentScenario();
        HeadroomTestData.makeLine(s.Id, 'Kenya', 'Core Program - KE', 'N/A', 'N/A', 'N/A', 'N/A', -5000000, 0, 0, 0);
        HeadroomTestData.makeLine(s.Id, 'Rwanda', 'Core Program - RW', 'N/A', 'N/A', 'N/A', 'N/A', -2000000, 0, 0, 0);
    }

    private static Id lineId(String bu) {
        return [SELECT Id FROM Budget_Line__c WHERE BusinessUnit__c = :bu LIMIT 1].Id;
    }

    private static AmaizePortfolioRisks.Result run(String metric, Integer topN) {
        AmaizePortfolioRisks.Request r = new AmaizePortfolioRisks.Request();
        r.metric = metric; r.fiscalYear = 2027; r.topN = topN;
        return AmaizePortfolioRisks.rank(new List<AmaizePortfolioRisks.Request>{ r })[0];
    }

    @isTest
    static void composesRankedPortfolioSummary() {
        HeadroomTestData.makeAllocations(new List<HeadroomTestData.AllocSpec>{
            new HeadroomTestData.AllocSpec('Pipeline', 2500000)
        }, lineId('Core Program - RW'), 'Rwanda', 'Core Program - RW');

        Test.startTest();
        AmaizePortfolioRisks.Result res = run('collision risk', 10);
        Test.stopTest();

        System.assertEquals(2, res.matchCount);
        System.assert(res.summary.contains('Portfolio Competing-Grant Risk'), res.summary);
        System.assert(res.summary.contains('Rwanda'), res.summary);
        System.assert(res.resultsJson.contains('"minimumAdjustmentRequired"'), res.resultsJson);
    }

    @isTest
    static void emptyWhenNoScopes() {
        // Filter to a country with no governed budget lines.
        AmaizePortfolioRisks.Request r = new AmaizePortfolioRisks.Request();
        r.metric = 'collision'; r.country = 'Nigeria'; r.fiscalYear = 2027;
        AmaizePortfolioRisks.Result res = AmaizePortfolioRisks.rank(new List<AmaizePortfolioRisks.Request>{ r })[0];
        System.assertEquals(0, res.matchCount);
        System.assert(res.summary.contains('No Headroom results'), res.summary);
    }

    @isTest
    static void performsNoDml() {
        Test.startTest();
        run('collision', 10);
        System.assertEquals(0, Limits.getDmlStatements(), 'Portfolio ranking must never write data');
        Test.stopTest();
    }
}
