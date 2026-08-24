@isTest
private class AgentAction_FindAccountTest {
    private class MockService implements IAccountService {
        private List<AccountSummary> toReturn;
        private MockService(List<AccountSummary> summaries) {
            this.toReturn = summaries;
        }
        public List<AccountSummary> findAccounts(String t, String type, Integer m) {
            return toReturn;
        }
    }

    private class ThrowingService implements IAccountService {
        public List<AccountSummary> findAccounts(String t, String type, Integer m) {
            throw new CalloutException('unexpected');
        }
    }

    private static AgentAction_FindAccount.Request req(String term) {
        AgentAction_FindAccount.Request r = new AgentAction_FindAccount.Request();
        r.searchTerm = term;
        return r;
    }

    private static AgentAction_FindAccount.Response run(AgentAction_FindAccount.Request r) {
        return AgentAction_FindAccount.findAccount(new List<AgentAction_FindAccount.Request>{ r })[0];
    }

    @isTest
    static void successPathReturnsResults() {
        AccountSummary s = new AccountSummary();
        s.id = '001000000000001AAA';
        s.name = 'Gates Foundation';
        AgentAction_FindAccount.service = new MockService(new List<AccountSummary>{ s });

        AgentAction_FindAccount.Response resp = run(req('gates'));

        System.assertEquals(true, resp.success);
        System.assertEquals(1, resp.count);
        System.assertEquals(1, resp.accounts.size());
        System.assert(resp.message.contains('1'), 'Message should reflect the count');
    }

    @isTest
    static void emptyPathReturnsFriendlyMessage() {
        AgentAction_FindAccount.service = new MockService(new List<AccountSummary>());

        AgentAction_FindAccount.Response resp = run(req('nothing'));

        System.assertEquals(true, resp.success);
        System.assertEquals(0, resp.count);
        System.assertEquals('No accounts matched your search.', resp.message);
        System.assertEquals(0, resp.accounts.size());
    }

    @isTest
    static void disabledFlagReturnsError() {
        FeatureFlag.setOverride(AgentAction_FindAccount.ACTION_NAME, false);

        AgentAction_FindAccount.Response resp = run(req('gates'));

        System.assertEquals(false, resp.success);
        System.assert(resp.message.contains('disabled'), 'Should report disabled: ' + resp.message);
    }

    @isTest
    static void unexpectedErrorReturnsSafeMessage() {
        AgentAction_FindAccount.service = new ThrowingService();

        AgentAction_FindAccount.Response resp = run(req('gates'));

        System.assertEquals(false, resp.success);
        System.assertEquals('Something went wrong while searching accounts.', resp.message);
    }
}