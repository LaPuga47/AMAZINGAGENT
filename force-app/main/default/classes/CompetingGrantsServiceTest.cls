/**
 * CompetingGrantsServiceTest — competition detection, exposure, and severity against the
 * Budget-Line-first engine. Allocations are created inside each test (the DLRS trigger +
 * org flows on the allocation chain are SOQL-heavy, so they stay out of @TestSetup).
 *
 * The Budget Line's stored funding fields are set to match the competing allocations, since
 * a scratch/sandbox transaction has no live rollup — the service reads headroom from those
 * stored fields and the competing detail from the allocations.
 */
@isTest
private class CompetingGrantsServiceTest {

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
    static void highWhenAllClosingWouldExceedHeadroom() {
        Id sid = [SELECT Id FROM Budget_Scenario__c WHERE Is_Current_Scenario__c = true LIMIT 1].Id;
        // Budget 5.0M. Funding rolls up FROM allocations: one Secured $3.2M (-> secured
        // headroom 1.8M) plus $2.8M of competing Likely/Pipeline. If all competing close it
        // overshoots by $1.0M (High), but the probability-weighted pipeline ($1.8M) does not
        // exceed headroom, so it is not Critical.
        Budget_Line__c line = HeadroomTestData.makeLine(sid, 'Kenya', 'Core Program - KE',
            'N/A', 'N/A', 'N/A', 'N/A', -5000000, 0, 0, 0);
        HeadroomTestData.makeAllocations(new List<HeadroomTestData.AllocSpec>{
            new HeadroomTestData.AllocSpec('Secured', 3200000),  // already secured
            new HeadroomTestData.AllocSpec('Likely', 1200000),   // Gates
            new HeadroomTestData.AllocSpec('Likely', 1000000),   // Mastercard
            new HeadroomTestData.AllocSpec('Pipeline', 600000)   // ABC
        }, line.Id, 'Kenya', 'Core Program - KE');

        Test.startTest();
        CompetingGrantsResult r = new CompetingGrantsService().analyze(dims('Kenya', 'Core Program - KE', '2027'));
        Test.stopTest();

        System.assertEquals(CompetingGrantsResult.Status.FOUND, r.status);
        System.assertEquals(4, r.grants.size(), 'One secured + three competing opportunities');
        System.assert(r.hasCompetition(), 'Should detect competition');
        System.assertEquals(2800000, r.combinedCompeting, 'Combined Likely+Pipeline allocated (secured excluded)');
        System.assertEquals(1800000, r.securedHeadroom);
        System.assertEquals(1000000, r.potentialExcess, 'Combined 2.8M - 1.8M headroom');
        System.assertEquals('High Competition', r.severity, 'All-close overshoots but prob-weighted does not');
    }

    @isTest
    static void criticalWhenAlreadyOverAllocatedOnSecured() {
        Id sid = [SELECT Id FROM Budget_Scenario__c WHERE Is_Current_Scenario__c = true LIMIT 1].Id;
        // Secured funding already exceeds the budget -> secured headroom is negative.
        Budget_Line__c line = HeadroomTestData.makeLine(sid, 'Malawi', 'Core Program - MW',
            'N/A', 'N/A', 'N/A', 'N/A', -5000000, 0, 0, 0);
        HeadroomTestData.makeAllocations(new List<HeadroomTestData.AllocSpec>{
            new HeadroomTestData.AllocSpec('Secured', 5500000),
            new HeadroomTestData.AllocSpec('Pipeline', 400000)
        }, line.Id, 'Malawi', 'Core Program - MW');

        Test.startTest();
        CompetingGrantsResult r = new CompetingGrantsService().analyze(dims('Malawi', 'Core Program - MW', '2027'));
        Test.stopTest();

        System.assertEquals(CompetingGrantsResult.Status.FOUND, r.status);
        System.assert(r.securedHeadroom < 0, 'Secured funding exceeds budget: ' + r.securedHeadroom);
        System.assertEquals('Critical / Over-allocated', r.severity);
    }

    @isTest
    static void noMaterialWhenHeadroomComfortablyExceedsPipeline() {
        Id sid = [SELECT Id FROM Budget_Scenario__c WHERE Is_Current_Scenario__c = true LIMIT 1].Id;
        // Big headroom (5M budget, 0 secured -> 5M), one small $0.3M pipeline.
        Budget_Line__c line = HeadroomTestData.makeLine(sid, 'Rwanda', 'Core Program - RW',
            'N/A', 'N/A', 'N/A', 'N/A', -5000000, 0, 0, 300000);
        HeadroomTestData.makeAllocations(new List<HeadroomTestData.AllocSpec>{
            new HeadroomTestData.AllocSpec('Pipeline', 300000)
        }, line.Id, 'Rwanda', 'Core Program - RW');

        Test.startTest();
        CompetingGrantsResult r = new CompetingGrantsService().analyze(dims('Rwanda', 'Core Program - RW', '2027'));
        Test.stopTest();

        System.assertEquals(CompetingGrantsResult.Status.FOUND, r.status);
        System.assertEquals(300000, r.combinedCompeting);
        System.assertEquals('No Material Competition', r.severity);
        System.assert(!r.hasCompetition(), 'One grant is not competition');
    }

    @isTest
    static void needsInfoWhenBusinessUnitMissing() {
        BudgetLineDimensions d = new BudgetLineDimensions();
        d.country = 'Kenya'; d.fiscalYear = '2027';   // no business unit
        CompetingGrantsResult r = new CompetingGrantsService().analyze(d);
        System.assertEquals(CompetingGrantsResult.Status.NEEDS_INFO, r.status);
        System.assert(r.missingDimensions.contains('business unit'), r.missingDimensions.toString());
    }

    @isTest
    static void notFoundWhenScopeHasNoBudgetLine() {
        CompetingGrantsResult r = new CompetingGrantsService().analyze(dims('Tanzania', 'Core Program', '2027'));
        System.assertEquals(CompetingGrantsResult.Status.NOT_FOUND, r.status);
    }

    @isTest
    static void resolvesCompetingGrantViaMatchKey() {
        Id sid = [SELECT Id FROM Budget_Scenario__c WHERE Is_Current_Scenario__c = true LIMIT 1].Id;
        // Allocation created before its Budget Line exists -> left unlinked (Match Key path).
        HeadroomTestData.makeAllocation('Likely', 400000, null,
            'Uganda', 'Core Program - UG', 'N/A', 'N/A', 'N/A', 'N/A');
        Budget_Line__c line = HeadroomTestData.makeLine(sid, 'Uganda', 'Core Program - UG',
            'N/A', 'N/A', 'N/A', 'N/A', -2000000, 500000, 400000, 0);

        Test.startTest();
        CompetingGrantsResult r = new CompetingGrantsService().analyze(dims('Uganda', 'Core Program - UG', '2027'));
        Test.stopTest();

        System.assertEquals(CompetingGrantsResult.Status.FOUND, r.status);
        System.assertEquals(1, r.grants.size(), 'The unlinked allocation should resolve via Match Key');
        System.assertEquals(400000, r.combinedCompeting);
    }
}
