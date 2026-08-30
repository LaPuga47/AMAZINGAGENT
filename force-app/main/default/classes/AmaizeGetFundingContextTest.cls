/**
 * AmaizeGetFundingContextTest — the Get Funding Context action: composed lineage summaries
 * for both directions, the needs-info message, and the read-only guardrail.
 */
@isTest
private class AmaizeGetFundingContextTest {

    @TestSetup
    static void setup() {
        HeadroomTestData.makeCurrentScenario();
    }

    private static AmaizeGetFundingContext.Result run(AmaizeGetFundingContext.Request r) {
        return AmaizeGetFundingContext.get(new List<AmaizeGetFundingContext.Request>{ r })[0];
    }

    @isTest
    static void budgetLineDirectionComposesFundingContext() {
        Id sid = [SELECT Id FROM Budget_Scenario__c WHERE Is_Current_Scenario__c = true LIMIT 1].Id;
        Budget_Line__c line = HeadroomTestData.makeLine(sid, 'Kenya', 'Core Program - KE',
            'N/A', 'N/A', 'N/A', 'N/A', -5000000, 0, 0, 0);
        HeadroomTestData.makeAllocations(new List<HeadroomTestData.AllocSpec>{
            new HeadroomTestData.AllocSpec('Secured', 3200000),
            new HeadroomTestData.AllocSpec('Likely', 1200000),
            new HeadroomTestData.AllocSpec('Pipeline', 600000)
        }, line.Id, 'Kenya', 'Core Program - KE');

        AmaizeGetFundingContext.Request req = new AmaizeGetFundingContext.Request();
        req.country = 'Kenya'; req.businessUnit = 'Core Program - KE'; req.fiscalYear = 2027;
        req.subUnit = 'N/A'; req.department = 'N/A'; req.costType = 'N/A'; req.costCategory = 'N/A';

        Test.startTest();
        AmaizeGetFundingContext.Result res = run(req);
        Test.stopTest();

        System.assertEquals(true, res.found);
        System.assert(res.summary.contains('**Funding Context'), res.summary);
        System.assert(res.summary.contains('**Funding Summary**'), res.summary);
        System.assert(res.summary.contains('**Funding Detail**'), res.summary);
        System.assert(res.summary.contains('**Competing Grants Insight**'), res.summary);
    }

    @isTest
    static void opportunityDirectionComposesLineage() {
        Id sid = [SELECT Id FROM Budget_Scenario__c WHERE Is_Current_Scenario__c = true LIMIT 1].Id;
        Budget_Line__c line = HeadroomTestData.makeLine(sid, 'Uganda', 'Core Program - UG',
            'N/A', 'N/A', 'N/A', 'N/A', -2000000, 0, 0, 0);
        Allocation__c alloc = HeadroomTestData.makeAllocation('Likely', 500000, line.Id,
            'Uganda', 'Core Program - UG', 'N/A', 'N/A', 'N/A', 'N/A');
        Allocation__c a = [SELECT Restriction__r.Gift_Commitment__r.OpportunityId FROM Allocation__c WHERE Id = :alloc.Id];
        Opportunity o = [SELECT Name FROM Opportunity WHERE Id = :a.Restriction__r.Gift_Commitment__r.OpportunityId];

        AmaizeGetFundingContext.Request req = new AmaizeGetFundingContext.Request();
        req.opportunityName = o.Name;

        Test.startTest();
        AmaizeGetFundingContext.Result res = run(req);
        Test.stopTest();

        System.assertEquals(true, res.found);
        System.assert(res.summary.contains('**Funding Lineage'), res.summary);
        System.assert(res.summary.contains('Budget Line exposure') || res.summary.contains('Allocated across'), res.summary);
    }

    @isTest
    static void needsInfoWhenNothingProvided() {
        AmaizeGetFundingContext.Result res = run(new AmaizeGetFundingContext.Request());
        System.assertEquals(false, res.found);
        System.assert(res.summary.containsIgnoreCase('grant') || res.summary.containsIgnoreCase('budget line'), res.summary);
    }

    @isTest
    static void actionPerformsNoDml() {
        Id sid = [SELECT Id FROM Budget_Scenario__c WHERE Is_Current_Scenario__c = true LIMIT 1].Id;
        HeadroomTestData.makeLine(sid, 'Kenya', 'Core Program - KE', 'N/A', 'N/A', 'N/A', 'N/A', -5000000, 0, 0, 0);
        AmaizeGetFundingContext.Request req = new AmaizeGetFundingContext.Request();
        req.country = 'Kenya'; req.businessUnit = 'Core Program - KE'; req.fiscalYear = 2027;
        req.subUnit = 'N/A'; req.department = 'N/A'; req.costType = 'N/A'; req.costCategory = 'N/A';
        Test.startTest();
        run(req);
        System.assertEquals(0, Limits.getDmlStatements(), 'Funding-context analysis must never write data');
        Test.stopTest();
    }
}
