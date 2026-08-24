/**
 * Tests for AmaizeSearchSimilarGrants — the Step 1 grant search.
 * Covers: multiple matches, no matches, Closed Lost exclusion, and the suggestion text.
 */
@isTest
private class AmaizeSearchSimilarGrantsTest {

    @TestSetup
    static void setup() {
        AmaizeTestData.makeAll();
    }

    private static AmaizeSearchSimilarGrants.Result run(String country, String theme) {
        AmaizeSearchSimilarGrants.Request req = new AmaizeSearchSimilarGrants.Request();
        req.country = country; req.theme = theme;
        return AmaizeSearchSimilarGrants.search(new List<AmaizeSearchSimilarGrants.Request>{ req })[0];
    }

    @isTest
    static void findsMultipleMatchesAndExcludesClosedLost() {
        // Kenya Core has 2 open grants + 1 Closed Lost. The Lost one must be excluded.
        Test.startTest();
        AmaizeSearchSimilarGrants.Result r = run('Kenya', 'Core Program');
        Test.stopTest();

        System.assertEquals(2, r.matchCount, 'Should find 2 open Kenya Core grants (Lost excluded)');
        System.assert(r.summary.contains('Greenfield'), 'Should list the Greenfield grant');
        System.assert(!r.summary.contains('Lost – Kenya'), 'Closed Lost grant must not appear');
        System.assert(r.summary.contains('associating'), 'Should suggest associating when grants exist');
    }

    @isTest
    static void noMatchesSuggestsNewOpportunity() {
        // Malawi Nutrition has no grants -> suggest creating a new opportunity.
        Test.startTest();
        AmaizeSearchSimilarGrants.Result r = run('Malawi', 'Nutrition');
        Test.stopTest();

        System.assertEquals(0, r.matchCount, 'Should find no matches');
        System.assert(r.summary.contains('no existing grants'), 'Should say there are none');
        System.assert(r.summary.contains('new opportunity'), 'Should suggest creating new');
        System.assertEquals('[]', r.resultsJson, 'JSON should be an empty array');
    }

    @isTest
    static void singleMatchUsesSingularGrammar() {
        // Kenya Carbon has exactly one grant -> "1 grant" phrasing.
        Test.startTest();
        AmaizeSearchSimilarGrants.Result r = run('Kenya', 'Carbon');
        Test.stopTest();
        System.assertEquals(1, r.matchCount, 'Should find the single Carbon grant');
        System.assert(r.summary.contains('Continental'), 'Should list the Continental grant');
    }
}