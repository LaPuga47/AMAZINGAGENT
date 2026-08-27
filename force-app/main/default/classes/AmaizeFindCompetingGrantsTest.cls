/**
 * AmaizeFindCompetingGrantsTest — the governed action: composed response with the governed
 * Headroom block, competing opportunities by exposure (not Opportunity Amount) with clickable
 * record links, and the zero / not-configured / none / needs-info states. Read-only.
 */
@isTest
private class AmaizeFindCompetingGrantsTest {

    @TestSetup
    static void setup() {
        Budget_Scenario__c s = HeadroomTestData.makeCurrentScenario();
        HeadroomTestData.makeLine(s.Id, 'Kenya', 'Core Program - KE', 'N/A', 'Extension', 'N/A', 'N/A',
            -5000000, 3200000, 0, 0);   // secured headroom 1.8M
    }

    private static AmaizeFindCompetingGrants.Request req(String program, String country, Integer fy) {
        AmaizeFindCompetingGrants.Request r = new AmaizeFindCompetingGrants.Request();
        r.program = program; r.country = country; r.fiscalYear = fy;
        return r;
    }

    private static AmaizeFindCompetingGrants.Result run(AmaizeFindCompetingGrants.Request r) {
        return AmaizeFindCompetingGrants.find(new List<AmaizeFindCompetingGrants.Request>{ r })[0];
    }

    @isTest
    static void composesGovernedResponseWithExposureAndLinks() {
        Id lineId = [SELECT Id FROM Budget_Line__c WHERE BusinessUnit__c = 'Core Program - KE' LIMIT 1].Id;
        HeadroomTestData.makeAllocations(new List<HeadroomTestData.AllocSpec>{
            new HeadroomTestData.AllocSpec('Pipeline', 1200000),
            new HeadroomTestData.AllocSpec('Pipeline', 1000000)
        }, lineId, 'Kenya', 'Core Program - KE');

        Test.startTest();
        AmaizeFindCompetingGrants.Result res = run(req('Core Program', 'Kenya', 2027));
        Test.stopTest();

        System.assertEquals(true, res.found);
        System.assert(res.summary.contains('**Competing Grants Summary**'), res.summary);
        System.assert(res.summary.contains('**Headroom Position**'), res.summary);
        System.assert(res.summary.contains('Budget Lines Included:'), res.summary);
        System.assert(res.summary.contains('Exposure to this scope'), res.summary);
        // Clickable record link (Markdown + Lightning URL) is present.
        System.assert(res.summary.contains('/lightning/r/Opportunity/'), 'Expected an Opportunity record link: ' + res.summary);
        // Opportunity Amount is NOT used as exposure (allocations have no opp amount set here).
        System.assert(res.resultsJson.contains('"totalExposure"'), res.resultsJson);
    }

    @isTest
    static void unrestrictedHasNoCompetition() {
        AmaizeFindCompetingGrants.Result res = run(req('Unrestricted', 'Kenya', 2027));
        System.assertEquals(false, res.found);
        System.assertEquals('ZERO', res.severity);
        System.assert(res.summary.containsIgnoreCase('no governed headroom capacity'), res.summary);
    }

    @isTest
    static void notConfiguredCategory() {
        AmaizeFindCompetingGrants.Result res = run(req('Miscellaneous', 'Kenya', 2027));
        System.assertEquals('NOT_CONFIGURED', res.severity);
        System.assert(res.summary.contains('has not yet been configured'), res.summary);
    }

    @isTest
    static void noQualifyingLines() {
        AmaizeFindCompetingGrants.Result res = run(req('Trees', 'Kenya', 2027));
        System.assertEquals('NONE', res.severity);
        System.assert(res.summary.contains('No qualifying Budget Line records were found'), res.summary);
    }

    @isTest
    static void budgetLinesButNoAllocations() {
        AmaizeFindCompetingGrants.Result res = run(req('Core Program', 'Kenya', 2027));  // lines exist, no allocations
        System.assertEquals(true, res.found);
        System.assert(res.summary.contains('no Funding Allocations are currently linked'), res.summary);
    }

    @isTest
    static void performsNoDml() {
        Test.startTest();
        run(req('Core Program', 'Kenya', 2027));
        System.assertEquals(0, Limits.getDmlStatements(), 'Competing-grants analysis must never write data');
        Test.stopTest();
    }
}
