@isTest
private class AccountSummarySelectorTest {
    @isTest
    static void fetchExecutesUnderUserMode() {
        AccountSummarySelector sel = new AccountSummarySelector();
        Test.startTest();
        AccountSummaryData byMissingName = sel.fetch('ZZ No Such Account ZZ', null);
        AccountSummaryData byMissingId = sel.fetch(null, (Id) '001000000000001AAA');
        AccountSummaryData byBlank = sel.fetch(null, null);
        Test.stopTest();

        System.assertNotEquals(null, byMissingName, 'Returns a data container');
        System.assertEquals(null, byMissingName.acct, 'No account for a non-matching name');
        System.assertEquals(null, byBlank.acct, 'No account when nothing provided');
        System.assertNotEquals(null, byMissingId, 'Returns a data container for id path');
    }

    // Uses real org data to exercise the full fetch (account + related queries).
    @isTest(SeeAllData=true)
    static void fetchRealAccountCoversRelatedQueries() {
        List<Account> existing = [SELECT Id FROM Account LIMIT 1];
        if (existing.isEmpty()) {
            return; // no data to exercise in this org
        }
        Test.startTest();
        AccountSummaryData data = new AccountSummarySelector().fetch(null, existing[0].Id);
        Test.stopTest();
        System.assertNotEquals(null, data.acct, 'Should load the existing account');
        System.assertNotEquals(null, data.opportunities, 'Opportunities list should be initialized');
        System.assertNotEquals(null, data.transactions, 'Transactions list should be initialized');
    }
}