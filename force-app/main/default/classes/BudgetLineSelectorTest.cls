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
        // Country-suffixed variants (the org's real naming convention) for suffix-tolerance tests.
        HeadroomTestData.makeLine(s.Id, 'Kenya', 'Core Program - KE', 'Input Costs', 'N/A', 'N/A', 'N/A',
            -700000, 200000, 0, 0);
        HeadroomTestData.makeLine(s.Id, 'Rwanda', 'Core Program - RW', 'N/A', 'N/A', 'N/A', 'N/A',
            -400000, 100000, 0, 0);
    }

    @isTest
    static void findByDimensionsBaseNameMatchesSuffixedVariant() {
        // A bare "Core Program" in Kenya should match both the bare and the "- KE" lines,
        // but never Rwanda's "- RW" variant (the query is country-scoped).
        BudgetLineSelector sel = new BudgetLineSelector();
        BudgetLineDimensions d = new BudgetLineDimensions();
        d.fiscalYear = '2027'; d.country = 'Kenya'; d.businessUnit = 'Core Program';
        List<Budget_Line__c> hits = sel.findByDimensions(d);
        Set<String> bus = new Set<String>();
        for (Budget_Line__c bl : hits) { bus.add(bl.BusinessUnit__c); }
        System.assert(bus.contains('Core Program'), 'Base line should match: ' + bus);
        System.assert(bus.contains('Core Program - KE'), 'Suffixed KE variant should match: ' + bus);
        System.assert(!bus.contains('Core Program - RW'), 'RW variant must not cross-match: ' + bus);
    }

    @isTest
    static void findByDimensionsSuffixedNameMatchesBaseVariant() {
        // Passing the suffixed "Core Program - KE" should also find the base-named Kenya lines.
        BudgetLineSelector sel = new BudgetLineSelector();
        BudgetLineDimensions d = new BudgetLineDimensions();
        d.fiscalYear = '2027'; d.country = 'Kenya'; d.businessUnit = 'Core Program - KE';
        Set<String> bus = new Set<String>();
        for (Budget_Line__c bl : sel.findByDimensions(d)) { bus.add(bl.BusinessUnit__c); }
        System.assert(bus.contains('Core Program - KE'), 'Suffixed line should match: ' + bus);
        System.assert(bus.contains('Core Program'), 'Base line should also match: ' + bus);
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
        // Two bare "Core Program" lines + the "Core Program - KE" variant (suffix tolerance).
        System.assertEquals(3, hits.size(), 'Country+BU+FY should match both base lines and the KE variant');
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
        System.assertEquals(3, sel.findPortfolio('Kenya', '2027').size());   // 2 base + 1 "- KE"
        System.assertEquals(2, sel.findPortfolio('Rwanda', '2027').size());  // 1 base + 1 "- RW"
        System.assertEquals(5, sel.findPortfolio(null, null).size(), 'No filter returns all current-scenario lines');
    }

    private static BudgetLineDimensions kenyaCore(String costCategory) {
        BudgetLineDimensions d = new BudgetLineDimensions();
        d.fiscalYear = '2027'; d.country = 'Kenya'; d.businessUnit = 'Core Program';
        d.subUnit = 'N/A'; d.department = 'N/A'; d.costType = 'N/A'; d.costCategory = costCategory;
        return d;
    }
}
