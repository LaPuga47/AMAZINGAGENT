@isTest
private class AgentAction_FindGiftCommitmentTest {
    private class MockService implements IGiftCommitmentService {
        private List<GiftCommitmentSummary> toReturn;
        private MockService(List<GiftCommitmentSummary> summaries) {
            this.toReturn = summaries;
        }
        public List<GiftCommitmentSummary> findGiftCommitments(String t, Id d, String s, Integer m) {
            return toReturn;
        }
    }

    private class ThrowingService implements IGiftCommitmentService {
        public List<GiftCommitmentSummary> findGiftCommitments(String t, Id d, String s, Integer m) {
            throw new CalloutException('unexpected');
        }
    }

    private static AgentAction_FindGiftCommitment.Request req(String term, String donorId) {
        AgentAction_FindGiftCommitment.Request r = new AgentAction_FindGiftCommitment.Request();
        r.searchTerm = term;
        r.donorId = donorId;
        return r;
    }

    private static AgentAction_FindGiftCommitment.Response run(AgentAction_FindGiftCommitment.Request r) {
        return AgentAction_FindGiftCommitment.findGiftCommitment(
            new List<AgentAction_FindGiftCommitment.Request>{ r }
        )[0];
    }

    @isTest
    static void successPathReturnsResults() {
        GiftCommitmentSummary s = new GiftCommitmentSummary();
        s.id = '0lp000000000001AAA';
        s.name = 'Multi-Year Pledge';
        AgentAction_FindGiftCommitment.service = new MockService(new List<GiftCommitmentSummary>{ s });

        AgentAction_FindGiftCommitment.Response resp = run(req('pledge', null));

        System.assertEquals(true, resp.success);
        System.assertEquals(1, resp.count);
        System.assertEquals(1, resp.giftCommitments.size());
    }

    @isTest
    static void emptyPathReturnsFriendlyMessage() {
        AgentAction_FindGiftCommitment.service = new MockService(new List<GiftCommitmentSummary>());

        AgentAction_FindGiftCommitment.Response resp = run(req('nothing', null));

        System.assertEquals(true, resp.success);
        System.assertEquals(0, resp.count);
        System.assertEquals('No gift commitments matched your search.', resp.message);
    }

    @isTest
    static void invalidDonorIdReturnsError() {
        AgentAction_FindGiftCommitment.Response resp = run(req(null, 'not-an-id'));

        System.assertEquals(false, resp.success);
        System.assert(resp.message.contains('valid Salesforce Id'), 'Should report the invalid Id: ' + resp.message);
    }

    @isTest
    static void disabledFlagReturnsError() {
        FeatureFlag.setOverride(AgentAction_FindGiftCommitment.ACTION_NAME, false);

        AgentAction_FindGiftCommitment.Response resp = run(req('pledge', null));

        System.assertEquals(false, resp.success);
        System.assert(resp.message.contains('disabled'), 'Should report disabled: ' + resp.message);
    }

    @isTest
    static void unexpectedErrorReturnsSafeMessage() {
        AgentAction_FindGiftCommitment.service = new ThrowingService();

        AgentAction_FindGiftCommitment.Response resp = run(req('pledge', null));

        System.assertEquals(false, resp.success);
        System.assertEquals('Something went wrong while searching gift commitments.', resp.message);
    }
}