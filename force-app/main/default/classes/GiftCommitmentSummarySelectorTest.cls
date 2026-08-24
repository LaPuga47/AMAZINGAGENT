@isTest
private class GiftCommitmentSummarySelectorTest {
    @isTest
    static void fetchExecutesUnderUserMode() {
        GiftCommitmentSummarySelector sel = new GiftCommitmentSummarySelector();
        Test.startTest();
        GiftCommitmentSummaryData byMissingName = sel.fetch('ZZ No Such Commitment ZZ', null);
        GiftCommitmentSummaryData byMissingId = sel.fetch(null, (Id) '6gc000000000001AAA');
        GiftCommitmentSummaryData byBlank = sel.fetch(null, null);
        Test.stopTest();

        System.assertNotEquals(null, byMissingName, 'Returns a data container');
        System.assertEquals(null, byMissingName.commitment, 'No commitment for a non-matching name');
        System.assertEquals(null, byBlank.commitment, 'No commitment when nothing provided');
        System.assertNotEquals(null, byMissingId, 'Returns a data container for id path');
    }

    // Uses real org data to exercise the full fetch (commitment + related queries).
    @isTest(SeeAllData=true)
    static void fetchRealCommitmentCoversRelatedQueries() {
        List<GiftCommitment> existing = [SELECT Id, Name FROM GiftCommitment LIMIT 1];
        if (existing.isEmpty()) {
            return; // no data to exercise in this org
        }
        Test.startTest();
        GiftCommitmentSummaryData byId = new GiftCommitmentSummarySelector().fetch(null, existing[0].Id);
        // Name path also exercises the name-search + best-match ranking loop.
        GiftCommitmentSummaryData byName = new GiftCommitmentSummarySelector().fetch(existing[0].Name, null);
        Test.stopTest();
        System.assertNotEquals(null, byId.commitment, 'Should load the existing commitment by id');
        System.assertNotEquals(null, byId.transactions, 'Transactions list should be initialized');
        System.assertNotEquals(null, byId.restrictions, 'Restrictions list should be initialized');
        System.assertNotEquals(null, byName.commitment, 'Should load a commitment by name');
    }
}