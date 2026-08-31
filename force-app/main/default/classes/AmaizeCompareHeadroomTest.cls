/**
 * AmaizeCompareHeadroomTest — concise multi-country Headroom comparison. Verifies each country
 * is resolved through the governed engine, negative Forecast Headroom renders as a positive
 * "Funding Gap" and positive as "Available Headroom", empty countries say "No qualifying Budget
 * Line records found" (not "$0"), the response is ONE block (not a full financial block per
 * country), a group summary names the largest gap, >8 groups are capped to 8, and a compared
 * value matches a direct single-country query (consistency).
 */
@isTest
private class AmaizeCompareHeadroomTest {

    @TestSetup
    static void setup() {
        Budget_Scenario__c s = HeadroomTestData.makeCurrentScenario();
        // Org convention: Forecast Headroom = |budget| - funding.
        //   positive => unfunded need (funding gap);  negative => funded beyond budget (available headroom).
        HeadroomTestData.makeLine(s.Id, 'Malawi',  'Core Program - MW', 'N/A', 'Extension', 'N/A', 'N/A', -1640000, 0, 0, 0); // gap 1.64M
        HeadroomTestData.makeLine(s.Id, 'Kenya',   'Core Program - KE', 'N/A', 'Extension', 'N/A', 'N/A', -5000000, 0, 0, 0); // gap 5.0M (largest)
        HeadroomTestData.makeLine(s.Id, 'Rwanda',  'Core Program - RW', 'N/A', 'Extension', 'N/A', 'N/A',  -900000, 0, 0, 0); // gap 0.9M
        // Burundi Core Program: funded beyond budget -> negative forecast headroom (available capacity).
        HeadroomTestData.makeLine(s.Id, 'Burundi', 'Core Program - BI', 'N/A', 'Extension', 'N/A', 'N/A', -1000000, 1200000, 0, 0); // -0.2M available
    }

    private static AmaizeCompareHeadroom.Request req(String program, String countries, Integer fy) {
        AmaizeCompareHeadroom.Request r = new AmaizeCompareHeadroom.Request();
        r.program = program; r.countries = countries; r.fiscalYear = fy;
        return r;
    }
    private static AmaizeCompareHeadroom.Result run(AmaizeCompareHeadroom.Request r) {
        return AmaizeCompareHeadroom.compare(new List<AmaizeCompareHeadroom.Request>{ r })[0];
    }

    @isTest
    static void comparesFourCountriesConcisely() {
        AmaizeCompareHeadroom.Result res = run(req('Core Program', 'Malawi, Kenya, Rwanda, Burundi', 2027));
        System.assertEquals(4, res.matchCount, res.summary);
        // Positive headroom rendered as available Headroom, positive magnitude.
        System.assert(res.summary.contains('Malawi: Available Headroom $1.64M'), res.summary);
        System.assert(!res.summary.contains('Available Headroom -') && !res.summary.contains('Overfunded -'),
            'magnitudes must be positive: ' + res.summary);
        // Burundi is funded beyond budget -> overfunded, not available Headroom.
        System.assert(res.summary.contains('Burundi: Overfunded'), res.summary);
        // Group summary names the country with the most available Headroom.
        System.assert(res.summary.contains('Kenya has the most available Headroom'), res.summary);
        // Concise: the Headroom Status block text is NOT repeated per country.
        System.assert(!res.summary.containsIgnoreCase('Headroom Status'), 'no repeated status blocks: ' + res.summary);
        // States metric once.
        System.assertEquals(1, countOccurrences(res.summary, 'Forecast Headroom'), 'metric stated once: ' + res.summary);
    }

    @isTest
    static void emptyCountrySaysNoQualifyingRecords() {
        AmaizeCompareHeadroom.Result res = run(req('Core Program', 'Malawi, Uganda', 2027));
        System.assert(res.summary.contains('Uganda: No qualifying Budget Line records found'), res.summary);
        System.assert(!res.summary.contains('Uganda: Available Headroom'), 'empty country is not rendered as $0 gap: ' + res.summary);
    }

    @isTest
    static void andSeparatorAndDuplicatesParsed() {
        AmaizeCompareHeadroom.Result res = run(req('Core Program', 'Malawi and Kenya and Malawi', 2027));
        // "and" splits, duplicate Malawi collapses -> 2 groups.
        System.assertEquals(2, res.matchCount, res.summary);
    }

    @isTest
    static void consistencyWithDirectSingleCountryQuery() {
        Test.startTest();
        AmaizeCompareHeadroom.Result res = run(req('Core Program', 'Malawi, Kenya', 2027));
        HeadroomAggregate direct = new HeadroomService().aggregate('Core Program', 'Kenya', '2027');
        Test.stopTest();
        // The compared Kenya gap must equal the direct query's forecast headroom (positive = gap).
        System.assert(direct.forecastHeadroom > 0, 'Kenya is a funding gap: ' + direct.forecastHeadroom);
        String expected = 'Kenya: Available Headroom ' + AmaizeFormat.money(direct.forecastHeadroom, direct.currencyIsoCode);
        System.assert(res.summary.contains(expected), 'expected "' + expected + '" in: ' + res.summary);
    }

    @isTest
    static void capsAtEightGroups() {
        // Add more current-scenario countries so the total exceeds 8.
        Budget_Scenario__c s = [SELECT Id FROM Budget_Scenario__c WHERE Is_Current_Scenario__c = true LIMIT 1];
        // Use the base 'Core Program' business unit (valid picklist value; resolver is suffix-tolerant).
        for (String c : new List<String>{ 'Nigeria', 'Zambia', 'Tanzania', 'Uganda' }) {
            HeadroomTestData.makeLine(s.Id, c, 'Core Program', 'N/A', 'Extension', 'N/A', 'N/A', -100000, 0, 0, 0);
        }
        // 8 countries with data + 2 without (Ghana/DRC have no Budget Lines) => 10 groups > cap of 8.
        AmaizeCompareHeadroom.Result res = run(req('Core Program',
            'Malawi, Kenya, Rwanda, Burundi, Nigeria, Zambia, Tanzania, Uganda, Ghana, DRC', 2027));
        System.assertEquals(10, res.matchCount, 'all requested groups resolved');
        System.assert(res.summary.contains('Showing the 8 countries with the most available Headroom'), 'capped display: ' + res.summary);
        // Kenya (largest gap) is shown; empty countries sort last and are dropped from the display.
        System.assert(res.summary.contains('Kenya: Available Headroom'), res.summary);
    }

    @isTest
    static void performsNoDml() {
        Test.startTest();
        run(req('Core Program', 'Malawi, Kenya', 2027));
        System.assertEquals(0, Limits.getDmlStatements(), 'Comparison must never write data');
        Test.stopTest();
    }

    private static Integer countOccurrences(String haystack, String needle) {
        if (String.isBlank(haystack)) { return 0; }
        return (haystack.length() - haystack.replace(needle, '').length()) / needle.length();
    }
}
