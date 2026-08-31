/**
 * AmaizeAnalyzeHeadroomTest — the governed Headroom aggregation action: category resolution,
 * summing all qualifying Budget Lines (not one, not averaged), the eight required fields +
 * line count, governed zero categories, not-configured, no-match, needs-info, and read-only.
 *
 * Budget Lines are created WITHOUT allocations, so the funding fields set here persist (the
 * org rollup only fires when allocations are attached) and the formula fields compute from them.
 */
@isTest
private class AmaizeAnalyzeHeadroomTest {

    @TestSetup
    static void setup() {
        Budget_Scenario__c s = HeadroomTestData.makeCurrentScenario();
        // HR-001 Core Program (Kenya): two lines that must be SUMMED.
        HeadroomTestData.makeLine(s.Id, 'Kenya', 'Core Program - KE', 'N/A', 'Extension', 'N/A', 'N/A',
            -1000000, 300000, 100000, 100000);   // secured HR 700k, forecast HR 500k
        HeadroomTestData.makeLine(s.Id, 'Kenya', 'Core Program - KE', 'N/A', 'Field Operations', 'N/A', 'N/A',
            -500000, 100000, 0, 0);               // secured HR 400k, forecast HR 400k
        // HR-002 Rural Retail (Farm Input Sales + Department = Rural Retail).
        HeadroomTestData.makeLine(s.Id, 'Kenya', 'Farm Input Sales - KE', 'N/A', 'Rural Retail', 'N/A', 'N/A',
            -800000, 500000, 0, 0);
        // A Farm Input Sales line under a DIFFERENT department (Trees) — must NOT be counted for Rural Retail.
        HeadroomTestData.makeLine(s.Id, 'Kenya', 'Farm Input Sales - KE', 'N/A', 'Trees', 'N/A', 'N/A',
            -300000, 50000, 0, 0);
    }

    private static AmaizeAnalyzeHeadroom.Request req(String program, String country, Integer fy) {
        AmaizeAnalyzeHeadroom.Request r = new AmaizeAnalyzeHeadroom.Request();
        r.program = program; r.country = country; r.fiscalYear = fy;
        return r;
    }

    private static AmaizeAnalyzeHeadroom.Result run(AmaizeAnalyzeHeadroom.Request r) {
        return AmaizeAnalyzeHeadroom.analyze(new List<AmaizeAnalyzeHeadroom.Request>{ r })[0];
    }

    @isTest
    static void coreProgramSumsAllQualifyingLines() {
        AmaizeAnalyzeHeadroom.Result res = run(req('Core Program', 'Kenya', 2027));
        System.assertEquals(true, res.found);
        System.assertEquals('Headroom Available', res.signal);
        // Budget 1.0M + 0.5M = 1.5M; secured 0.3M + 0.1M = 0.4M; secured HR 0.7M + 0.4M = 1.1M.
        System.assert(res.headroomJson.contains('"budgetAmount":1500000'), res.headroomJson);
        System.assert(res.headroomJson.contains('"securedFunding":400000'), res.headroomJson);
        System.assert(res.headroomJson.contains('"securedHeadroom":1100000'), res.headroomJson);
        System.assert(res.headroomJson.contains('"budgetLinesIncluded":2'), res.headroomJson);
        // The full field-by-field breakdown lives in detail, not the default conversational summary.
        System.assert(res.detail.contains('Budget Lines Included: 2'), res.detail);
        System.assert(!res.summary.contains('Budget Lines Included'), 'summary must be conversational: ' + res.summary);
    }

    @isTest
    static void ruralRetailFiltersByDepartmentOnly() {
        AmaizeAnalyzeHeadroom.Result res = run(req('Rural Retail', 'Kenya', 2027));
        System.assertEquals(true, res.found);
        // Only the Rural Retail line (0.8M budget, 0.5M secured) — NOT the Trees line.
        System.assert(res.headroomJson.contains('"budgetAmount":800000'), res.headroomJson);
        System.assert(res.headroomJson.contains('"budgetLinesIncluded":1'), res.headroomJson);
    }

    @isTest
    static void unrestrictedIsGovernedZero() {
        AmaizeAnalyzeHeadroom.Result res = run(req('Unrestricted', 'Kenya', 2027));
        System.assertEquals(true, res.found);
        System.assertEquals('Not Applicable', res.signal);
        System.assert(res.detail.contains('Headroom Status: Not Applicable'), res.detail);
        System.assert(res.summary.contains('defined as zero'), res.summary);
    }

    @isTest
    static void workingCapitalIsGovernedZero() {
        AmaizeAnalyzeHeadroom.Result res = run(req('Working Capital', 'Kenya', 2027));
        System.assertEquals('Not Applicable', res.signal);
    }

    @isTest
    static void miscellaneousIsNotConfigured() {
        AmaizeAnalyzeHeadroom.Result res = run(req('Miscellaneous', 'Kenya', 2027));
        System.assertEquals(false, res.found);
        System.assertEquals('NOT_CONFIGURED', res.signal);
        System.assert(res.summary.contains('has not yet been configured'), res.summary);
    }

    @isTest
    static void noQualifyingLinesIsNotZero() {
        AmaizeAnalyzeHeadroom.Result res = run(req('Systems Change', 'Kenya', 2027));  // none seeded
        System.assertEquals(false, res.found);
        System.assertEquals('NONE', res.signal);
        System.assert(res.summary.contains('No qualifying Budget Line records were found'), res.summary);
    }

    @isTest
    static void missingCountryNeedsInfo() {
        AmaizeAnalyzeHeadroom.Result res = run(req('Core Program', null, 2027));
        System.assertEquals(false, res.found);
        System.assertEquals('NEEDS_INFO', res.signal);
        System.assert(res.summary.contains('country'), res.summary);
    }

    @isTest
    static void positiveEqualHeadroomIsConciseAndSingleNumber() {
        // Rural Retail: secured HR = forecast HR = 300K (no likely/pipeline) -> concise, one number.
        AmaizeAnalyzeHeadroom.Result res = run(req('Rural Retail', 'Kenya', 2027));
        System.assertEquals(true, res.found);
        System.assert(res.summary.contains('room for additional fundraising'), res.summary);
        System.assert(res.summary.contains('available Headroom'), res.summary);
        System.assert(res.summary.contains('currently secured'), res.summary);
        System.assert(res.summary.contains('no likely or pipeline funding'), res.summary);
        // Equal secured/forecast -> do NOT expose both similar numbers.
        System.assert(!res.summary.contains('falls to'), 'no secured-vs-forecast split when equal: ' + res.summary);
        System.assert(res.summary.contains('grants already funding'), 'contextual follow-up: ' + res.summary);
    }

    @isTest
    static void materiallyDifferentSecuredVsForecastShowsBoth() {
        // Core Program: secured HR 1.1M vs forecast HR 0.9M (200K likely+pipeline) -> both surfaced.
        AmaizeAnalyzeHeadroom.Result res = run(req('Core Program', 'Kenya', 2027));
        System.assert(res.summary.contains('tighter'), res.summary);
        System.assert(res.summary.contains('Secured Headroom'), res.summary);
        System.assert(res.summary.contains('falls to'), res.summary);
        System.assert(res.summary.contains('pipeline Opportunities'), 'tight-case follow-up: ' + res.summary);
    }

    @isTest
    static void negativeHeadroomSaysNoAvailableHeadroom() {
        Budget_Scenario__c s = [SELECT Id FROM Budget_Scenario__c WHERE Is_Current_Scenario__c = true LIMIT 1];
        // Rwanda Trees over-allocated: budget 500K, secured 1.0M -> forecast HR -500K.
        HeadroomTestData.makeLine(s.Id, 'Rwanda', 'Farm Input Sales - RW', 'N/A', 'Trees', 'N/A', 'N/A',
            -500000, 1000000, 0, 0);
        AmaizeAnalyzeHeadroom.Result res = run(req('Trees', 'Rwanda', 2027));
        System.assertEquals(true, res.found);
        System.assert(res.summary.contains('is currently overfunded by'), res.summary);
        System.assert(res.summary.contains('funding exceeds its available capacity'), res.summary);
        System.assert(!res.summary.contains('room for additional fundraising'), res.summary);
        System.assert(res.summary.contains('consuming the current capacity'), 'over-allocated follow-up: ' + res.summary);
    }

    @isTest
    static void zeroHeadroomSaysFullyFunded() {
        Budget_Scenario__c s = [SELECT Id FROM Budget_Scenario__c WHERE Is_Current_Scenario__c = true LIMIT 1];
        // Burundi Core Program fully funded: budget 500K, secured 500K -> forecast HR 0.
        HeadroomTestData.makeLine(s.Id, 'Burundi', 'Core Program - BI', 'N/A', 'Extension', 'N/A', 'N/A',
            -500000, 500000, 0, 0);
        AmaizeAnalyzeHeadroom.Result res = run(req('Core Program', 'Burundi', 2027));
        System.assert(res.summary.contains('fully funded'), res.summary);
        System.assert(!res.summary.contains('room for additional fundraising'), res.summary);
    }

    @isTest
    static void detailCarriesFullBreakdownOnDemand() {
        AmaizeAnalyzeHeadroom.Result res = run(req('Core Program', 'Kenya', 2027));
        for (String f : new List<String>{ 'Budget Amount', 'Secured Funding', 'Likely Funding',
                'Pipeline Funding', 'Forecast Funding', 'Secured Headroom', 'Forecast Headroom',
                'Headroom Status', 'Budget Lines Included' }) {
            System.assert(res.detail.contains(f), 'detail missing ' + f + ': ' + res.detail);
        }
    }

    @isTest
    static void summaryUsesNaturalNameNotBusinessUnit() {
        AmaizeAnalyzeHeadroom.Result res = run(req('Rural Retail', 'Kenya', 2027));
        System.assert(res.summary.contains('Kenya Rural Retail'), res.summary);
        System.assert(!res.summary.contains('Farm Input Sales'), 'no internal business unit: ' + res.summary);
        System.assert(!res.summary.contains(' - KE'), 'no suffixed unit: ' + res.summary);
    }

    @isTest
    static void performsNoDml() {
        Test.startTest();
        run(req('Core Program', 'Kenya', 2027));
        run(req('Unrestricted', 'Kenya', 2027));
        System.assertEquals(0, Limits.getDmlStatements(), 'Governed aggregation must never write data');
        Test.stopTest();
    }
}
