/**
 * AmaizeAnalyzeHeadroomTest — the single-Budget-Line action: response composition for
 * each outcome (found / over-allocated / ambiguous / needs-info / not-found), currency
 * preservation (#preserve currencies), and the read-only guardrail (#20).
 */
@isTest
private class AmaizeAnalyzeHeadroomTest {

    @TestSetup
    static void setup() {
        Budget_Scenario__c s = HeadroomTestData.makeCurrentScenario();
        HeadroomTestData.makeLine(s.Id, 'Kenya', 'Core Program', 'N/A', 'N/A', 'N/A', 'N/A',
            -1000000, 300000, 100000, 100000);                 // Headroom Available
        HeadroomTestData.makeLine(s.Id, 'Kenya', 'Core Program', 'N/A', 'N/A', 'N/A', 'Salary',
            -500000, 100000, 0, 0);
        HeadroomTestData.makeLine(s.Id, 'Kenya', 'Field Building', 'N/A', 'N/A', 'N/A', 'N/A',
            -500000, 400000, 200000, 100000);                  // over-allocated (-200k)
    }

    private static AmaizeAnalyzeHeadroom.Request req(String country, String bu, Integer fy,
            String sub, String dept, String ct, String cc) {
        AmaizeAnalyzeHeadroom.Request r = new AmaizeAnalyzeHeadroom.Request();
        r.country = country; r.businessUnit = bu; r.fiscalYear = fy;
        r.subUnit = sub; r.department = dept; r.costType = ct; r.costCategory = cc;
        return r;
    }

    private static AmaizeAnalyzeHeadroom.Result run(AmaizeAnalyzeHeadroom.Request r) {
        return AmaizeAnalyzeHeadroom.analyze(new List<AmaizeAnalyzeHeadroom.Request>{ r })[0];
    }

    @isTest
    static void foundSummaryReportsAllFundingTypes() {
        AmaizeAnalyzeHeadroom.Result res = run(req('Kenya', 'Core Program', 2027, 'N/A', 'N/A', 'N/A', 'N/A'));
        System.assertEquals(true, res.found);
        System.assertEquals('Headroom Available', res.signal);
        System.assert(res.summary.contains('Secured funding'), res.summary);
        System.assert(res.summary.contains('likely funding'), res.summary);
        System.assert(res.summary.contains('pipeline funding'), res.summary);
        System.assert(res.summary.contains('headroom'), res.summary);
        System.assert(res.headroomJson.contains('"forecastHeadroom":500000'), res.headroomJson);
    }

    @isTest
    static void overAllocatedSummaryExplainsNegativeHeadroom() {
        AmaizeAnalyzeHeadroom.Result res = run(req('Kenya', 'Field Building', 2027, 'N/A', 'N/A', 'N/A', 'N/A'));
        System.assertEquals(true, res.found);
        System.assert(res.summary.contains('over-allocated'), res.summary);
    }

    @isTest
    static void ambiguousAsksToChoose() {
        AmaizeAnalyzeHeadroom.Result res = run(req('Kenya', 'Core Program', 2027, null, null, null, null));
        System.assertEquals(false, res.found);
        System.assertEquals('AMBIGUOUS', res.signal);
        System.assert(res.summary.contains('differ by'), res.summary);
    }

    @isTest
    static void needsInfoAsksForFiscalYearAndSubUnit() {
        AmaizeAnalyzeHeadroom.Result res = run(req('Kenya', 'Core Program', null, null, null, null, null));
        System.assertEquals(false, res.found);
        System.assertEquals('NEEDS_INFO', res.signal);
        System.assert(res.summary.contains('fiscal year'), res.summary);
        System.assert(res.summary.containsIgnoreCase('N/A'), 'Should offer N/A for the sub-unit: ' + res.summary);
    }

    @isTest
    static void notFoundIsHonest() {
        AmaizeAnalyzeHeadroom.Result res = run(req('Tanzania', 'Core Program', 2027, 'N/A', 'N/A', 'N/A', 'N/A'));
        System.assertEquals(false, res.found);
        System.assertEquals('NOT_FOUND', res.signal);
        System.assert(res.summary.containsIgnoreCase('couldn\'t find'), res.summary);
    }

    // Currency preservation — the ISO-aware formatter used by the summaries.
    @isTest
    static void moneyPreservesNonUsdCurrency() {
        System.assertEquals('$1.2M', AmaizeFormat.money(1200000, 'USD'));
        System.assertEquals('$1.2M', AmaizeFormat.money(1200000, null));
        System.assertEquals('KES 1.2M', AmaizeFormat.money(1200000, 'KES'));
        System.assertEquals('-EUR 150K', AmaizeFormat.money(-150000, 'EUR'));
    }

    // #20 — read-only guardrail: the action path performs NO DML.
    @isTest
    static void actionPerformsNoDml() {
        Test.startTest();
        Integer before = Limits.getDmlStatements();
        run(req('Kenya', 'Core Program', 2027, 'N/A', 'N/A', 'N/A', 'N/A'));
        run(req('Kenya', 'Core Program', 2027, null, null, null, null)); // ambiguous path
        System.assertEquals(before, Limits.getDmlStatements(), 'Headroom analysis must never write data');
        System.assertEquals(0, Limits.getDmlStatements(), 'No DML expected in the read-only action');
        Test.stopTest();
    }
}
