/**
 * Tests that HeadroomKeyBuilder reproduces the org's composite key EXACTLY — same
 * dimension order, UPPER/TRIM, and pipe delimiter — so a key built in Apex resolves
 * the same Budget Line the platform's Budget_Line_Unique_Key__c formula produces.
 */
@isTest
private class HeadroomKeyBuilderTest {

    @isTest
    static void buildsKeyInDeclarativeOrderWithUpperAndTrim() {
        BudgetLineDimensions d = new BudgetLineDimensions();
        d.fiscalYear = ' 2027 ';
        d.country = 'Kenya';
        d.businessUnit = 'core program';
        d.subUnit = 'N/A';
        d.costType = 'N/A';
        d.department = 'N/A';
        d.costCategory = 'Staff Costs';

        // Order MUST be FY | Country | BU | Sub | CostType | Dept | CostCategory.
        System.assertEquals('2027|KENYA|CORE PROGRAM|N/A|N/A|N/A|STAFF COSTS',
            HeadroomKeyBuilder.build(d), 'Key format/order must mirror the org formulas');
    }

    @isTest
    static void nullDimensionsBecomeEmptySegments() {
        BudgetLineDimensions d = new BudgetLineDimensions();
        d.fiscalYear = '2027';
        d.country = 'Kenya';
        // everything else null
        System.assertEquals('2027|KENYA|||||', HeadroomKeyBuilder.build(d),
            'Null dimensions must render as empty segments, matching TEXT(null)');
    }

    @isTest
    static void nullDimensionsObjectIsSafe() {
        System.assertEquals('||||||', HeadroomKeyBuilder.build(null),
            'A null dimensions object must not throw');
    }

    @isTest
    static void matchesRealBudgetLineUniqueKey() {
        Budget_Scenario__c s = HeadroomTestData.makeCurrentScenario();
        Budget_Line__c bl = HeadroomTestData.makeLine(s.Id, 'Kenya', 'Core Program',
            'N/A', 'N/A', 'N/A', 'N/A', -1000000, 300000, 100000, 100000);

        BudgetLineDimensions d = new BudgetLineDimensions();
        d.fiscalYear = bl.Fiscal_Year__c;
        d.country = bl.Country__c;
        d.businessUnit = bl.BusinessUnit__c;
        d.subUnit = bl.Sub__c;
        d.costType = bl.Cost_Type__c;
        d.department = bl.Department__c;
        d.costCategory = bl.Cost_Category__c;

        System.assertEquals(bl.Budget_Line_Unique_Key__c, HeadroomKeyBuilder.build(d),
            'Apex-built key must equal the org-generated Budget_Line_Unique_Key__c');
    }
}
