/**
 * AmaizeRankHeadroomTest — the portfolio action: ranking output, the over-allocated
 * view, the empty case, and that Budget Lines are listed separately (never merged).
 */
@isTest
private class AmaizeRankHeadroomTest {

    @TestSetup
    static void setup() {
        Budget_Scenario__c s = HeadroomTestData.makeCurrentScenario();
        HeadroomTestData.makeLine(s.Id, 'Kenya', 'Core Program', 'N/A', 'N/A', 'N/A', 'N/A',
            -1000000, 300000, 100000, 100000);                 // forecast +500k
        HeadroomTestData.makeLine(s.Id, 'Kenya', 'Farm Input Sales', 'N/A', 'N/A', 'N/A', 'N/A',
            -3000000, 200000, 0, 0);                            // forecast +2.8M (biggest room)
        HeadroomTestData.makeLine(s.Id, 'Kenya', 'Field Building', 'N/A', 'N/A', 'N/A', 'N/A',
            -500000, 400000, 200000, 100000);                  // forecast -200k (over-allocated)
    }

    private static AmaizeRankHeadroom.Request req(String filter, String country, Integer fy) {
        AmaizeRankHeadroom.Request r = new AmaizeRankHeadroom.Request();
        r.statusFilter = filter; r.country = country; r.fiscalYear = fy;
        return r;
    }

    private static AmaizeRankHeadroom.Result run(AmaizeRankHeadroom.Request r) {
        return AmaizeRankHeadroom.rank(new List<AmaizeRankHeadroom.Request>{ r })[0];
    }

    @isTest
    static void ranksMostHeadroomFirstAndListsEachSeparately() {
        AmaizeRankHeadroom.Result res = run(req('most headroom', 'Kenya', 2027));
        System.assertEquals(2, res.matchCount, 'Two Kenya lines have positive headroom');
        // Biggest room first, each Budget Line kept distinct (not merged).
        System.assert(res.summary.indexOf('Farm Input Sales') < res.summary.indexOf('Core Program'),
            'Farm Input Sales (2.8M) should rank above Core Program (500k): ' + res.summary);
        System.assert(res.summary.contains('Core Program'), res.summary);
    }

    @isTest
    static void overAllocatedFilterReturnsOnlyNegative() {
        AmaizeRankHeadroom.Result res = run(req('over-allocated', 'Kenya', 2027));
        System.assertEquals(1, res.matchCount);
        System.assert(res.summary.contains('Field Building'), res.summary);
        System.assert(res.summary.contains('over-allocated'), res.summary);
    }

    @isTest
    static void emptyWhenNoMatches() {
        AmaizeRankHeadroom.Result res = run(req('most headroom', 'Nigeria', 2027));
        System.assertEquals(0, res.matchCount);
        System.assert(res.summary.contains('no Budget Lines'), res.summary);
    }

    @isTest
    static void performsNoDml() {
        Test.startTest();
        run(req('all', 'Kenya', 2027));
        System.assertEquals(0, Limits.getDmlStatements(), 'Portfolio ranking must never write data');
        Test.stopTest();
    }
}
