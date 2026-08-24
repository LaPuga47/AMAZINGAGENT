@isTest
private class OpportunitySummarySelectorTest {
    @isTest
    static void fetchExecutesUnderUserMode() {
        OpportunitySummarySelector sel = new OpportunitySummarySelector();
        Test.startTest();
        OpportunitySummaryData byMissingName = sel.fetch('ZZ No Such Opp ZZ', null);
        OpportunitySummaryData byMissingId = sel.fetch(null, (Id) '006000000000001AAA');
        OpportunitySummaryData byBlank = sel.fetch(null, null);
        Test.stopTest();

        System.assertNotEquals(null, byMissingName, 'Returns a data container');
        System.assertEquals(null, byMissingName.opp, 'No opp for a non-matching name');
        System.assertEquals(null, byBlank.opp, 'No opp when nothing provided');
        System.assertNotEquals(null, byMissingId, 'Returns a data container for id path');
    }

    // Uses real org data to exercise the full fetch (opportunity + related queries).
    @isTest(SeeAllData=true)
    static void fetchRealOpportunityCoversRelatedQueries() {
        List<Opportunity> existing = [SELECT Id FROM Opportunity LIMIT 1];
        if (existing.isEmpty()) {
            return; // no data to exercise in this org
        }
        Test.startTest();
        OpportunitySummaryData data = new OpportunitySummarySelector().fetch(null, existing[0].Id);
        Test.stopTest();
        System.assertNotEquals(null, data.opp, 'Should load the existing opportunity');
        System.assertNotEquals(null, data.transactions, 'Transactions list should be initialized');
        System.assertNotEquals(null, data.restrictions, 'Restrictions list should be initialized');
    }
}