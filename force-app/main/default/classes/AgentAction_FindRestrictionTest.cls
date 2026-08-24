@isTest
private class AgentAction_FindRestrictionTest {
    private class MockService implements IRestrictionService {
        private List<RestrictionSummary> toReturn;
        private MockService(List<RestrictionSummary> summaries) {
            this.toReturn = summaries;
        }
        public List<RestrictionSummary> findRestrictions(String t, Id g, Id o, String c, Integer m) {
            return toReturn;
        }
    }

    private class ThrowingService implements IRestrictionService {
        public List<RestrictionSummary> findRestrictions(String t, Id g, Id o, String c, Integer m) {
            throw new CalloutException('unexpected');
        }
    }

    private static AgentAction_FindRestriction.Request req(String term, String giftCommitmentId) {
        AgentAction_FindRestriction.Request r = new AgentAction_FindRestriction.Request();
        r.searchTerm = term;
        r.giftCommitmentId = giftCommitmentId;
        return r;
    }

    private static AgentAction_FindRestriction.Response run(AgentAction_FindRestriction.Request r) {
        return AgentAction_FindRestriction.findRestriction(new List<AgentAction_FindRestriction.Request>{ r })[0];
    }

    @isTest
    static void successPathReturnsResults() {
        RestrictionSummary s = new RestrictionSummary();
        s.id = 'a0L000000000001AAA';
        s.name = 'Seed Program Restriction';
        AgentAction_FindRestriction.service = new MockService(new List<RestrictionSummary>{ s });

        AgentAction_FindRestriction.Response resp = run(req('seed', null));

        System.assertEquals(true, resp.success);
        System.assertEquals(1, resp.count);
        System.assertEquals(1, resp.restrictions.size());
    }

    @isTest
    static void emptyPathReturnsFriendlyMessage() {
        AgentAction_FindRestriction.service = new MockService(new List<RestrictionSummary>());

        AgentAction_FindRestriction.Response resp = run(req('nothing', null));

        System.assertEquals(true, resp.success);
        System.assertEquals(0, resp.count);
        System.assertEquals('No restrictions matched your search.', resp.message);
    }

    @isTest
    static void invalidGiftCommitmentIdReturnsError() {
        AgentAction_FindRestriction.Response resp = run(req(null, 'not-an-id'));

        System.assertEquals(false, resp.success);
        System.assert(resp.message.contains('valid Salesforce Id'), 'Should report the invalid Id: ' + resp.message);
    }

    @isTest
    static void disabledFlagReturnsError() {
        FeatureFlag.setOverride(AgentAction_FindRestriction.ACTION_NAME, false);

        AgentAction_FindRestriction.Response resp = run(req('seed', null));

        System.assertEquals(false, resp.success);
        System.assert(resp.message.contains('disabled'), 'Should report disabled: ' + resp.message);
    }

    @isTest
    static void unexpectedErrorReturnsSafeMessage() {
        AgentAction_FindRestriction.service = new ThrowingService();

        AgentAction_FindRestriction.Response resp = run(req('seed', null));

        System.assertEquals(false, resp.success);
        System.assertEquals('Something went wrong while searching restrictions.', resp.message);
    }
}