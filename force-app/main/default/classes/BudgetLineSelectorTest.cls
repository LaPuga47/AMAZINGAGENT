/**
 * Tests BudgetLineSelector: exact composite-key lookup, progressive structured-field
 * matching (with N/A treated as a real value), and the portfolio query — all scoped
 * to the current scenario.
 */
@isTest
private class BudgetLineSelectorTest {

    @TestSetup
    static void setup() {
        Budget_Scenario__c s = HeadroomTestData.makeCurrentScenario();
        // Two Kenya / Core Program lines differing only by Cost Category (ambiguity source).
        HeadroomTestData.makeLine(s.Id, 'Kenya', 'Core Program', 'N/A', 'N/A', 'N/A', 'N/A',
            -1000000, 300000, 100000, 100000);
        HeadroomTestData.makeLine(s.Id, 'Kenya', 'Core Program', 'N/A', 'N/A', 'N/A', 'Salary',
            -500000, 100000, 0, 0);
        // A single Rwanda line.
        HeadroomTestData.makeLine(s.Id, 'Rwanda', 'Farm Input Sales', 'N/A', 'N/A', 'N/A', 'N/A',
            -2000000, 500000, 0, 0);
    }

    @isTest
    static void findByUniqueKeyReturnsExactlyOne() {
        BudgetLineSelector sel = new BudgetLineSelector();
        BudgetLineDimensions d = kenyaCore('N/A');
        List<Budget_Line__c> hits = sel.findByUniqueKey(HeadroomKeyBuilder.build(d));
        System.assertEquals(1, hits.size(), 'Exact key should resolve one Budget Line');
        System.assertEquals('N/A', hits[0].Cost_Category__c);
    }

    @isTest
    static void findByUniqueKeyBlankReturnsEmpty() {
        System.assertEquals(0, new BudgetLineSelector().findByUniqueKey('   ').size());
    }

    @isTest
    static void findByDimensionsPartialReturnsAllMatches() {
        BudgetLineSelector sel = new BudgetLineSelector();
        BudgetLineDimensions d = new BudgetLineDimensions();
        d.fiscalYear = '2027'; d.country = 'Kenya'; d.businessUnit = 'Core Program';
        List<Budget_Line__c> hits = sel.findByDimensions(d);
        System.assertEquals(2, hits.size(), 'Country+BU+FY should match both Kenya/Core Program lines');
    }

    @isTest
    static void findByDimensionsTreatsNAAsRealValue() {
        BudgetLineSelector sel = new BudgetLineSelector();
        BudgetLineDimensions d = kenyaCore('N/A');
        List<Budget_Line__c> hits = sel.findByDimensions(d);
        System.assertEquals(1, hits.size(), 'Cost Category = N/A must be matched, not ignored');
        System.assertEquals('N/A', hits[0].Cost_Category__c);
    }

    @isTest
    static void findPortfolioScopesByCountry() {
        BudgetLineSelector sel = new BudgetLineSelector();
        System.assertEquals(2, sel.findPortfolio('Kenya', '2027').size());
        System.assertEquals(1, sel.findPortfolio('Rwanda', '2027').size());
        System.assertEquals(3, sel.findPortfolio(null, null).size(), 'No filter returns all current-scenario lines');
    }

    private static BudgetLineDimensions kenyaCore(String costCategory) {
        BudgetLineDimensions d = new BudgetLineDimensions();
        d.fiscalYear = '2027'; d.country = 'Kenya'; d.businessUnit = 'Core Program';
        d.subUnit = 'N/A'; d.department = 'N/A'; d.costType = 'N/A'; d.costCategory = costCategory;
        return d;
    }
}
