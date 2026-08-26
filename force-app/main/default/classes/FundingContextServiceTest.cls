/**
 * FundingContextServiceTest — bidirectional funding-lineage navigation:
 * Budget-Line direction (what funds a scope), Opportunity direction (where a grant is
 * allocated), plus needs-info / not-found / ambiguity and dedup. Allocations are created
 * inside each test (the allocation chain is SOQL-heavy) with funding driven via allocations
 * so the org rollup produces the headroom figures.
 */
@isTest
private class FundingContextServiceTest {

    @TestSetup
    static void setup() {
        HeadroomTestData.makeCurrentScenario();
    }

    private static BudgetLineDimensions dims(String country, String bu, String fy) {
        BudgetLineDimensions d = new BudgetLineDimensions();
        d.country = country; d.businessUnit = bu; d.fiscalYear = fy;
        d.subUnit = 'N/A'; d.department = 'N/A'; d.costType = 'N/A'; d.costCategory = 'N/A';
        return d;
    }

    @isTest
    static void budgetLineDirectionReturnsLineageAndAnalysis() {
        Id sid = [SELECT Id FROM Budget_Scenario__c WHERE Is_Current_Scenario__c = true LIMIT 1].Id;
        Budget_Line__c line = HeadroomTestData.makeLine(sid, 'Kenya', 'Core Program - KE',
            'N/A', 'N/A', 'N/A', 'N/A', -5000000, 0, 0, 0);
        HeadroomTestData.makeAllocations(new List<HeadroomTestData.AllocSpec>{
            new HeadroomTestData.AllocSpec('Secured', 3200000),
            new HeadroomTestData.AllocSpec('Likely', 1200000),
            new HeadroomTestData.AllocSpec('Pipeline', 600000)
        }, line.Id, 'Kenya', 'Core Program - KE');

        Test.startTest();
        FundingContext fc = new FundingContextService().forBudgetLineScope(dims('Kenya', 'Core Program - KE', '2027'));
        Test.stopTest();

        System.assertEquals(FundingContext.Status.FOUND_BUDGET_LINE, fc.status);
        System.assertEquals(1, fc.budgetLines.size());
        System.assertEquals(3, fc.allocations.size(), 'All three allocations form the lineage');
        System.assertEquals(1800000, fc.combinedCompeting, 'Likely 1.2M + Pipeline 0.6M');
        System.assertEquals(1800000, fc.securedHeadroom, '5.0M budget - 3.2M secured');
        // Combined competing (1.8M) equals headroom (1.8M) -> Moderate (High needs strictly greater).
        System.assertEquals('Moderate Competition', fc.severity);
        // Lineage traversal reaches the Opportunity + donor on at least one allocation.
        Boolean reachedGrant = false;
        for (Allocation__c a : fc.allocations) {
            if (a.Restriction__r != null && a.Restriction__r.Gift_Commitment__r != null
                    && a.Restriction__r.Gift_Commitment__r.Opportunity != null) { reachedGrant = true; }
        }
        System.assert(reachedGrant, 'Allocation -> Restriction -> Gift Commitment -> Opportunity lineage resolves');
    }

    @isTest
    static void opportunityDirectionFindsBudgetLines() {
        Id sid = [SELECT Id FROM Budget_Scenario__c WHERE Is_Current_Scenario__c = true LIMIT 1].Id;
        Budget_Line__c line = HeadroomTestData.makeLine(sid, 'Rwanda', 'Core Program - RW',
            'N/A', 'N/A', 'N/A', 'N/A', -2000000, 0, 0, 0);
        Allocation__c alloc = HeadroomTestData.makeAllocation('Likely', 500000, line.Id,
            'Rwanda', 'Core Program - RW', 'N/A', 'N/A', 'N/A', 'N/A');

        // The org's after-save flow rewrites the Opportunity name; read the real one.
        Allocation__c a = [SELECT Restriction__r.Gift_Commitment__r.OpportunityId FROM Allocation__c WHERE Id = :alloc.Id];
        Opportunity o = [SELECT Name FROM Opportunity WHERE Id = :a.Restriction__r.Gift_Commitment__r.OpportunityId];

        Test.startTest();
        FundingContext fc = new FundingContextService().forOpportunity(o.Name);
        Test.stopTest();

        System.assertEquals(FundingContext.Status.FOUND_OPPORTUNITY, fc.status);
        System.assertEquals(1, fc.allocations.size());
        System.assertEquals(1, fc.budgetLines.size(), 'The grant funds one Budget Line');
        System.assertEquals(line.Id, fc.budgetLines[0].Id);
    }

    @isTest
    static void budgetLineDirectionNeedsInfoWhenBusinessUnitMissing() {
        BudgetLineDimensions d = new BudgetLineDimensions();
        d.country = 'Kenya'; d.fiscalYear = '2027';
        FundingContext fc = new FundingContextService().forBudgetLineScope(d);
        System.assertEquals(FundingContext.Status.NEEDS_INFO, fc.status);
    }

    @isTest
    static void budgetLineDirectionNotFound() {
        FundingContext fc = new FundingContextService().forBudgetLineScope(dims('Tanzania', 'Core Program', '2027'));
        System.assertEquals(FundingContext.Status.NOT_FOUND, fc.status);
    }

    @isTest
    static void opportunityDirectionNotFound() {
        FundingContext fc = new FundingContextService().forOpportunity('Nonexistent Grant Zzzq');
        System.assertEquals(FundingContext.Status.NOT_FOUND, fc.status);
    }

    @isTest
    static void opportunityDirectionNeedsInfoWhenBlank() {
        FundingContext fc = new FundingContextService().forOpportunity('   ');
        System.assertEquals(FundingContext.Status.NEEDS_INFO, fc.status);
    }
}
