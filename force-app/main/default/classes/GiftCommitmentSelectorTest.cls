@isTest
private class GiftCommitmentSelectorTest {
    @isTest
    static void queryExecutesUnderUserModeForAllFilters() {
        GiftCommitmentSelector sel = new GiftCommitmentSelector();
        Test.startTest();
        List<GiftCommitment> all = sel.search(null, null, null, null);
        List<GiftCommitment> byTermAndStatus = sel.search('test', null, 'Active', 5);
        List<GiftCommitment> byDonor = sel.search(null, (Id) '001000000000001AAA', null, 3);
        Test.stopTest();

        System.assertNotEquals(null, all, 'Unfiltered query should return a list');
        System.assertNotEquals(null, byTermAndStatus, 'Filtered query should return a list');
        System.assertNotEquals(null, byDonor, 'Donor-filtered query should return a list');
    }
}