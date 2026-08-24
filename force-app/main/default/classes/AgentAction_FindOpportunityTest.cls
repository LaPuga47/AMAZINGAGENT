@isTest
private class AgentAction_FindOpportunityTest {
    private class MockService implements IOpportunityService {
        private List<OpportunitySummary> toReturn;
        private MockService(List<OpportunitySummary> summaries) {
            this.toReturn = summaries;
        }
        public List<OpportunitySummary> findOpportunities(String t, Id a, String s, Integer m) {
            return toReturn;
        }
    }

    private class ThrowingService implements IOpportunityService {
        public List<OpportunitySummary> findOpportunities(String t, Id a, String s, Integer m) {
            throw new CalloutException('unexpected');
        }
    }

    private static AgentAction_FindOpportunity.Request req(String term, String accountId) {
        AgentAction_FindOpportunity.Request r = new AgentAction_FindOpportunity.Request();
        r.searchTerm = term;
        r.accountId = accountId;
        return r;
    }

    private static AgentAction_FindOpportunity.Response run(AgentAction_FindOpportunity.Request r) {
        return AgentAction_FindOpportunity.findOpportunity(new List<AgentAction_FindOpportunity.Request>{ r })[0];
    }

    @isTest
    static void successPathReturnsResults() {
        OpportunitySummary s = new OpportunitySummary();
        s.id = '006000000000001AAA';
        s.name = 'Solar Grant';
        AgentAction_FindOpportunity.service = new MockService(new List<OpportunitySummary>{ s });

        AgentAction_FindOpportunity.Response resp = run(req('solar', null));

        System.assertEquals(true, resp.success);
        System.assertEquals(1, resp.count);
        System.assertEquals(1, resp.opportunities.size());
        System.assert(resp.message.contains('1'), 'Message should reflect the count');
    }

    @isTest
    static void emptyPathReturnsFriendlyMessage() {
        AgentAction_FindOpportunity.service = new MockService(new List<OpportunitySummary>());

        AgentAction_FindOpportunity.Response resp = run(req('nothing', null));

        System.assertEquals(true, resp.success);
        System.assertEquals(0, resp.count);
        System.assertEquals('No opportunities matched your search.', resp.message);
        System.assertEquals(0, resp.opportunities.size());
    }

    @isTest
    static void invalidAccountIdReturnsError() {
        AgentAction_FindOpportunity.Response resp = run(req(null, 'not-an-id'));

        System.assertEquals(false, resp.success);
        System.assert(resp.message.contains('valid Salesforce Id'), 'Should report the invalid Id: ' + resp.message);
    }

    @isTest
    static void disabledFlagReturnsError() {
        FeatureFlag.setOverride(AgentAction_FindOpportunity.ACTION_NAME, false);

        AgentAction_FindOpportunity.Response resp = run(req('solar', null));

        System.assertEquals(false, resp.success);
        System.assert(resp.message.contains('disabled'), 'Should report disabled: ' + resp.message);
    }

    @isTest
    static void unexpectedErrorReturnsSafeMessage() {
        AgentAction_FindOpportunity.service = new ThrowingService();

        AgentAction_FindOpportunity.Response resp = run(req('solar', null));

        System.assertEquals(false, resp.success);
        System.assertEquals('Something went wrong while searching opportunities.', resp.message);
    }
}