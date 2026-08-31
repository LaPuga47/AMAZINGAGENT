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
    static void twoOrMorePipelineIsConciseAndCompeting() {
        Id lineId = [SELECT Id FROM Budget_Line__c WHERE BusinessUnit__c = 'Core Program - KE' LIMIT 1].Id;
        HeadroomTestData.makeAllocations(new List<HeadroomTestData.AllocSpec>{
            new HeadroomTestData.AllocSpec('Pipeline', 1200000),
            new HeadroomTestData.AllocSpec('Pipeline', 1000000)
        }, lineId, 'Kenya', 'Core Program - KE');

        Test.startTest();
        AmaizeFindCompetingGrants.Result res = run(req('Core Program', 'Kenya', 2027));
        Test.stopTest();

        System.assertEquals(true, res.found);
        // Concise default: 2+ pipeline opportunities => a competing situation.
        System.assert(res.summary.startsWith('Yes.'), res.summary);
        System.assert(res.summary.contains('Two Opportunities may use the remaining'), res.summary);
        System.assert(res.summary.contains('**Potential Funding**'), res.summary);
        System.assert(res.summary.contains('Together, they represent'), res.summary);
        // No implementation terminology in the concise view.
        System.assert(!res.summary.contains('mapped') && !res.summary.contains('FY'), 'no FY/mapped: ' + res.summary);
        // Clickable Opportunity link in the concise view.
        System.assert(res.summary.contains('/lightning/r/Opportunity/'), 'Expected an Opportunity link: ' + res.summary);
        // The verbose analysis is NOT in the default summary...
        System.assert(!res.summary.contains('**Risk & Confidence**'), 'summary must be concise: ' + res.summary);
        System.assert(!res.summary.contains('**Headroom Position**'), 'no full breakdown by default: ' + res.summary);
        System.assert(!res.summary.contains('Budget Lines Included:'), res.summary);
        // ...it lives in detail, on demand.
        System.assert(res.detail.contains('**Risk & Confidence**'), res.detail);
        System.assert(res.detail.contains('**Headroom Position**'), res.detail);
        System.assert(res.detail.contains('Budget Lines Included:'), res.detail);
        System.assert(res.detail.contains('**Why They Compete**'), res.detail);
        System.assert(res.resultsJson.contains('"exposureToCurrentScope"'), res.resultsJson);
        System.assert(res.resultsJson.contains('"analysisConfidence"'), res.resultsJson);
    }

    @isTest
    static void onePipelineIsNotCompeting() {
        Id lineId = [SELECT Id FROM Budget_Line__c WHERE BusinessUnit__c = 'Core Program - KE' LIMIT 1].Id;
        HeadroomTestData.makeAllocations(new List<HeadroomTestData.AllocSpec>{
            new HeadroomTestData.AllocSpec('Pipeline', 900000)
        }, lineId, 'Kenya', 'Core Program - KE');

        Test.startTest();
        AmaizeFindCompetingGrants.Result res = run(req('Core Program', 'Kenya', 2027));
        Test.stopTest();

        System.assertEquals(true, res.found);
        // A SINGLE opportunity is NOT "competing".
        System.assert(res.summary.contains('one Opportunity that may use'), res.summary);
        System.assert(res.summary.contains('not yet a competing-grants situation'), res.summary);
        System.assert(!res.summary.contains('competing for'), 'single opp must not be called competing: ' + res.summary);
        System.assert(!res.summary.contains('Together the'), res.summary);
        System.assert(res.summary.contains('/lightning/r/Opportunity/'), res.summary);
    }

    @isTest
    static void securedOnlyMeansNoCompetition() {
        Id lineId = [SELECT Id FROM Budget_Line__c WHERE BusinessUnit__c = 'Core Program - KE' LIMIT 1].Id;
        HeadroomTestData.makeAllocations(new List<HeadroomTestData.AllocSpec>{
            new HeadroomTestData.AllocSpec('Secured', 500000)
        }, lineId, 'Kenya', 'Core Program - KE');

        Test.startTest();
        AmaizeFindCompetingGrants.Result res = run(req('Core Program', 'Kenya', 2027));
        Test.stopTest();

        System.assertEquals(true, res.found);
        // Secured contributor but no pipeline/likely => no competition.
        System.assert(res.summary.startsWith('No.'), res.summary);
        System.assert(res.summary.contains('did not find any Opportunities that may use'), res.summary);
        System.assert(res.summary.contains('currently secured'), res.summary);
    }

    @isTest
    static void unrestrictedHasNoCompetition() {
        AmaizeFindCompetingGrants.Result res = run(req('Unrestricted', 'Kenya', 2027));
        System.assertEquals(false, res.found);
        System.assertEquals('ZERO', res.severity);
        System.assert(res.summary.containsIgnoreCase('no Headroom capacity'), res.summary);
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
        System.assert(res.summary.contains('no funding is recorded against them'), res.summary);
    }

    @isTest
    static void performsNoDml() {
        Test.startTest();
        run(req('Core Program', 'Kenya', 2027));
        System.assertEquals(0, Limits.getDmlStatements(), 'Competing-grants analysis must never write data');
        Test.stopTest();
    }
}
