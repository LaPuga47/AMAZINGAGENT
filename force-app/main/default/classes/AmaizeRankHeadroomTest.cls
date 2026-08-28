/**
 * AmaizeRankHeadroomTest — portfolio ranking at the governed PROGRAM level: aggregates all
 * qualifying Budget Lines into Country + governed Category + Fiscal Year groups, ranks the
 * aggregates (not individual lines), returns the top N (default 8), uses canonical category
 * labels, and omits cost dimensions / per-row status / record counts. Includes the
 * consistency check that a ranked value equals a direct single-scope headroom query.
 */
@isTest
private class AmaizeRankHeadroomTest {

    @TestSetup
    static void setup() {
        Budget_Scenario__c s = HeadroomTestData.makeCurrentScenario();
        // Kenya Core Program — TWO lines with different cost dimensions -> must aggregate to ONE group.
        HeadroomTestData.makeLine(s.Id, 'Kenya', 'Core Program - KE', 'N/A', 'Extension', 'N/A', 'N/A',
            -1000000, 0, 0, 0);   // forecast headroom 1.0M
        HeadroomTestData.makeLine(s.Id, 'Kenya', 'Core Program - KE', 'N/A', 'Field Operations', 'N/A', 'Salary',
            -500000, 0, 0, 0);    // forecast headroom 0.5M  (same group -> 1.5M total)
        // Rwanda Trees (Farm Input Sales + Department = Trees).
        HeadroomTestData.makeLine(s.Id, 'Rwanda', 'Farm Input Sales - RW', 'N/A', 'Trees', 'N/A', 'N/A',
            -1200000, 0, 0, 0);   // 1.2M
        // Kenya Rural Retail.
        HeadroomTestData.makeLine(s.Id, 'Kenya', 'Farm Input Sales - KE', 'N/A', 'Rural Retail', 'N/A', 'N/A',
            -800000, 0, 0, 0);    // 0.8M
    }

    private static AmaizeRankHeadroom.Request req(String metric, String country, Integer fy, String category, Integer topN) {
        AmaizeRankHeadroom.Request r = new AmaizeRankHeadroom.Request();
        r.metric = metric; r.country = country; r.fiscalYear = fy; r.category = category; r.topN = topN;
        return r;
    }
    private static AmaizeRankHeadroom.Result run(AmaizeRankHeadroom.Request r) {
        return AmaizeRankHeadroom.rank(new List<AmaizeRankHeadroom.Request>{ r })[0];
    }

    @isTest
    static void aggregatesByProgramAndRanksByForecastHeadroom() {
        AmaizeRankHeadroom.Result res = run(req('largest funding gap', null, 2027, null, null));
        // Three distinct governed groups (Kenya Core Program counted ONCE despite two lines).
        System.assertEquals(3, res.matchCount, res.resultsJson);
        // Ranked most forecast headroom first: Kenya Core Program (1.5M) > Rwanda Trees (1.2M) > Kenya Rural Retail (0.8M).
        System.assert(res.summary.indexOf('Kenya - Core Program') < res.summary.indexOf('Rwanda - Trees'), res.summary);
        System.assert(res.summary.indexOf('Rwanda - Trees') < res.summary.indexOf('Kenya - Rural Retail'), res.summary);
        System.assert(res.resultsJson.contains('"forecastHeadroom":1500000'), 'Kenya Core Program aggregates 1.0M+0.5M: ' + res.resultsJson);
    }

    @isTest
    static void usesCanonicalLabelsAndNoTechnicalNoise() {
        AmaizeRankHeadroom.Result res = run(req(null, null, 2027, null, null));
        System.assert(!res.summary.contains('(Headroom Available)'), 'no per-row status: ' + res.summary);
        System.assert(!res.summary.containsIgnoreCase('Found '), 'no "Found N Budget Lines": ' + res.summary);
        System.assert(!res.summary.contains('Salary'), 'no cost-dimension labels: ' + res.summary);
        System.assert(!res.summary.contains('Extension'), 'no sub-unit/department labels: ' + res.summary);
        System.assert(!res.summary.contains('- KE'), 'no internal suffixed business unit: ' + res.summary);
        System.assert(res.summary.contains('Kenya - Core Program'), res.summary);
    }

    @isTest
    static void topNOverrideRespected() {
        AmaizeRankHeadroom.Result res = run(req('most headroom', null, 2027, null, 2));
        System.assertEquals(2, res.matchCount);
    }

    @isTest
    static void categoryFilterLimitsToOneProgram() {
        AmaizeRankHeadroom.Result res = run(req('most headroom', null, 2027, 'Core Program', null));
        System.assertEquals(1, res.matchCount);
        System.assert(res.summary.contains('Kenya - Core Program'), res.summary);
    }

    @isTest
    static void rankedValueMatchesDirectHeadroomQuery() {
        Test.startTest();
        List<HeadroomAggregate> ranked = new HeadroomService().rankPortfolioByCategory(
            'largest funding gap', 'Kenya', '2027', 'Core Program', 8);
        HeadroomAggregate direct = new HeadroomService().aggregate('Core Program', 'Kenya', '2027');
        Test.stopTest();
        System.assertEquals(1, ranked.size());
        // Consistency: portfolio ranking and a direct headroom query agree for the same scope.
        System.assertEquals(direct.forecastHeadroom, ranked[0].forecastHeadroom);
        System.assertEquals(direct.securedHeadroom, ranked[0].securedHeadroom);
        System.assertEquals(direct.budgetAmount, ranked[0].budgetAmount);
        System.assertEquals(direct.budgetLinesIncluded, ranked[0].budgetLinesIncluded);
    }

    @isTest
    static void performsNoDml() {
        Test.startTest();
        run(req('largest funding gap', null, 2027, null, null));
        System.assertEquals(0, Limits.getDmlStatements(), 'Ranking must never write data');
        Test.stopTest();
    }
}
