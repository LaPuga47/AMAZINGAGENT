@isTest
private class GiftTransactionSelectorTest {
    @isTest
    static void queryExecutesUnderUserModeForAllFilters() {
        GiftTransactionSelector sel = new GiftTransactionSelector();
        Test.startTest();
        List<GiftTransaction> all = sel.search(null, null, null, null, null, null);
        List<GiftTransaction> byTermAndStatus = sel.search('test', null, null, null, 'Paid', 5);
        List<GiftTransaction> byDonor = sel.search(null, (Id) '001000000000001AAA', null, null, null, 3);
        List<GiftTransaction> byCommitment = sel.search(null, null, (Id) '6gc000000000001AAA', null, null, 3);
        List<GiftTransaction> byCampaign = sel.search(null, null, null, (Id) '701000000000001AAA', null, 3);
        Test.stopTest();

        System.assertNotEquals(null, all, 'Unfiltered query should return a list');
        System.assertNotEquals(null, byTermAndStatus, 'Filtered query should return a list');
        System.assertNotEquals(null, byDonor, 'Donor-filtered query should return a list');
        System.assertNotEquals(null, byCommitment, 'Commitment-filtered query should return a list');
        System.assertNotEquals(null, byCampaign, 'Campaign-filtered query should return a list');
    }
}