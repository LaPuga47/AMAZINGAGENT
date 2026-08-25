/**
 * AmaizeFindCompetingGrantsTest — the action layer: composed summary sections, severity/
 * exposure outputs, the read-only guardrail, and the needs-info / not-found messages.
 */
@isTest
private class AmaizeFindCompetingGrantsTest {

    @TestSetup
    static void setup() {
        HeadroomTestData.makeCurrentScenario();
    }

    private static AmaizeFindCompetingGrants.Request req(String country, String bu, Integer fy) {
        AmaizeFindCompetingGrants.Request r = new AmaizeFindCompetingGrants.Request();
        r.country = country; r.businessUnit = bu; r.fiscalYear = fy;
        r.subUnit = 'N/A'; r.department = 'N/A'; r.costType = 'N/A'; r.costCategory = 'N/A';
        return r;
    }

    private static AmaizeFindCompetingGrants.Result run(AmaizeFindCompetingGrants.Request r) {
        return AmaizeFindCompetingGrants.find(new List<AmaizeFindCompetingGrants.Request>{ r })[0];
    }

    @isTest
    static void composesDecisionReadySummary() {
        Id sid = [SELECT Id FROM Budget_Scenario__c WHERE Is_Current_Scenario__c = true LIMIT 1].Id;
        Budget_Line__c line = HeadroomTestData.makeLine(sid, 'Kenya', 'Core Program - KE',
            'N/A', 'N/A', 'N/A', 'N/A', -5000000, 0, 0, 0);
        HeadroomTestData.makeAllocations(new List<HeadroomTestData.AllocSpec>{
            new HeadroomTestData.AllocSpec('Secured', 3200000),
            new HeadroomTestData.AllocSpec('Likely', 1200000),
            new HeadroomTestData.AllocSpec('Likely', 1000000),
            new HeadroomTestData.AllocSpec('Pipeline', 600000)
        }, line.Id, 'Kenya', 'Core Program - KE');

        Test.startTest();
        AmaizeFindCompetingGrants.Result res = run(req('Kenya', 'Core Program - KE', 2027));
        Test.stopTest();

        System.assertEquals(true, res.found);
        System.assertEquals('High Competition', res.severity);
        System.assertEquals(2800000, res.combinedPipeline);
        System.assertEquals(1800000, res.remainingHeadroom);
        // Response contains the designed sections.
        System.assert(res.summary.contains('**Competing Grants Summary**'), res.summary);
        System.assert(res.summary.contains('**Program Headroom**'), res.summary);
        System.assert(res.summary.contains('**Competing Opportunities**'), res.summary);
        System.assert(res.summary.contains('**Scenario Impact**'), res.summary);
        System.assert(res.summary.contains('Competition severity: High'), res.summary);
        System.assert(res.summary.contains('Suggested Coordination'), 'High should suggest coordination');
    }

    @isTest
    static void needsInfoWhenBusinessUnitMissing() {
        AmaizeFindCompetingGrants.Request r = req('Kenya', null, 2027);
        AmaizeFindCompetingGrants.Result res = run(r);
        System.assertEquals(false, res.found);
        System.assertEquals('NEEDS_INFO', res.severity);
        System.assert(res.summary.contains('business unit'), res.summary);
    }

    @isTest
    static void notFoundWhenScopeMissing() {
        AmaizeFindCompetingGrants.Result res = run(req('Tanzania', 'Core Program', 2027));
        System.assertEquals(false, res.found);
        System.assertEquals('NOT_FOUND', res.severity);
        System.assert(res.summary.containsIgnoreCase('couldn\'t find'), res.summary);
    }

    @isTest
    static void actionPerformsNoDml() {
        Id sid = [SELECT Id FROM Budget_Scenario__c WHERE Is_Current_Scenario__c = true LIMIT 1].Id;
        HeadroomTestData.makeLine(sid, 'Kenya', 'Core Program - KE',
            'N/A', 'N/A', 'N/A', 'N/A', -5000000, 3200000, 0, 0);
        Test.startTest();
        Integer before = Limits.getDmlStatements();
        run(req('Kenya', 'Core Program - KE', 2027));
        System.assertEquals(before, Limits.getDmlStatements(), 'Competing-grants analysis must never write data');
        Test.stopTest();
    }
}
