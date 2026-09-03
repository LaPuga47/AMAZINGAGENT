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
    static void naCostDimsAreRelaxedWhenScopeHasRealDimensions() {
        // A program line with REAL cost dimensions (Field Operations / Crop Insurance).
        Id sid = [SELECT Id FROM Budget_Scenario__c WHERE Is_Current_Scenario__c = true LIMIT 1].Id;
        Budget_Line__c line = HeadroomTestData.makeLine(sid, 'Malawi', 'Core Program - MW',
            'N/A', 'Field Operations', 'N/A', 'Crop Insurance', -800000, 100000, 0, 0);
        HeadroomTestData.makeAllocations(new List<HeadroomTestData.AllocSpec>{
            new HeadroomTestData.AllocSpec('Secured', 60000)
        }, line.Id, 'Malawi', 'Core Program - MW');

        // The planner default-fills every unspecified cost dimension with 'N/A'. Strictly filtering
        // on N/A would exclude this line (its Department is Field Operations), but the action relaxes
        // the N/A filters when the strict query finds nothing.
        AmaizeGetFundingContext.Request req = new AmaizeGetFundingContext.Request();
        req.country = 'Malawi'; req.businessUnit = 'Core Program - MW'; req.fiscalYear = 2027;
        req.subUnit = 'N/A'; req.department = 'N/A'; req.costType = 'N/A'; req.costCategory = 'N/A';

        Test.startTest();
        AmaizeGetFundingContext.Result res = run(req);
        Test.stopTest();

        System.assertEquals(true, res.found, 'N/A over-constraint must relax to find the real line: ' + res.summary);
        System.assert(res.summary.contains('**Funding Context'), res.summary);
    }

    @isTest
    static void explicitNonMatchingDimensionIsNotRelaxed() {
        // Same real line, but the user explicitly names a different, non-matching Cost Category.
        Id sid = [SELECT Id FROM Budget_Scenario__c WHERE Is_Current_Scenario__c = true LIMIT 1].Id;
        HeadroomTestData.makeLine(sid, 'Malawi', 'Core Program - MW',
            'N/A', 'Field Operations', 'N/A', 'Crop Insurance', -800000, 100000, 0, 0);

        AmaizeGetFundingContext.Request req = new AmaizeGetFundingContext.Request();
        req.country = 'Malawi'; req.businessUnit = 'Core Program - MW'; req.fiscalYear = 2027;
        req.costCategory = 'Input Costs';   // real value, deliberately specified — must be respected

        Test.startTest();
        AmaizeGetFundingContext.Result res = run(req);
        Test.stopTest();

        // No 'N/A' was passed, so there is no relaxation: an explicit non-matching dimension stands.
        System.assertEquals(false, res.found, 'An explicitly named dimension must not be relaxed: ' + res.summary);
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
