@isTest
private class RestrictionSelectorTest {
    @isTest
    static void queryExecutesUnderUserModeForAllFilters() {
        RestrictionSelector sel = new RestrictionSelector();
        Test.startTest();
        List<Restriction__c> all = sel.search(null, null, null, null, null);
        List<Restriction__c> byTermAndCountry = sel.search('test', null, null, 'Rwanda', 5);
        List<Restriction__c> byCommitment = sel.search(null, (Id) '6gc000000000001AAA', null, null, 3);
        List<Restriction__c> byOpportunity = sel.search(null, null, (Id) '006000000000001AAA', null, 3);
        Test.stopTest();

        System.assertNotEquals(null, all, 'Unfiltered query should return a list');
        System.assertNotEquals(null, byTermAndCountry, 'Filtered query should return a list');
        System.assertNotEquals(null, byCommitment, 'Commitment-filtered query should return a list');
        System.assertNotEquals(null, byOpportunity, 'Opportunity-filtered query should return a list');
    }
}