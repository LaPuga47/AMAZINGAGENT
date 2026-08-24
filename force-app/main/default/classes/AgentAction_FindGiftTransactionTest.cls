@isTest
private class AgentAction_FindGiftTransactionTest {
    private class MockService implements IGiftTransactionService {
        private List<GiftTransactionSummary> toReturn;
        private MockService(List<GiftTransactionSummary> summaries) {
            this.toReturn = summaries;
        }
        public List<GiftTransactionSummary> findGiftTransactions(String t, Id d, Id g, Id c, String s, Integer m) {
            return toReturn;
        }
    }

    private class ThrowingService implements IGiftTransactionService {
        public List<GiftTransactionSummary> findGiftTransactions(String t, Id d, Id g, Id c, String s, Integer m) {
            throw new CalloutException('unexpected');
        }
    }

    private static AgentAction_FindGiftTransaction.Request req(String term, String donorId) {
        AgentAction_FindGiftTransaction.Request r = new AgentAction_FindGiftTransaction.Request();
        r.searchTerm = term;
        r.donorId = donorId;
        return r;
    }

    private static AgentAction_FindGiftTransaction.Response run(AgentAction_FindGiftTransaction.Request r) {
        return AgentAction_FindGiftTransaction.findGiftTransaction(
            new List<AgentAction_FindGiftTransaction.Request>{ r }
        )[0];
    }

    @isTest
    static void successPathReturnsResults() {
        GiftTransactionSummary s = new GiftTransactionSummary();
        s.id = '6tr000000000001AAA';
        s.name = 'GT-0001';
        AgentAction_FindGiftTransaction.service = new MockService(new List<GiftTransactionSummary>{ s });

        AgentAction_FindGiftTransaction.Response resp = run(req('gt', null));

        System.assertEquals(true, resp.success);
        System.assertEquals(1, resp.count);
        System.assertEquals(1, resp.giftTransactions.size());
    }

    @isTest
    static void emptyPathReturnsFriendlyMessage() {
        AgentAction_FindGiftTransaction.service = new MockService(new List<GiftTransactionSummary>());

        AgentAction_FindGiftTransaction.Response resp = run(req('nothing', null));

        System.assertEquals(true, resp.success);
        System.assertEquals(0, resp.count);
        System.assertEquals('No gift transactions matched your search.', resp.message);
    }

    @isTest
    static void invalidDonorIdReturnsError() {
        AgentAction_FindGiftTransaction.Response resp = run(req(null, 'not-an-id'));

        System.assertEquals(false, resp.success);
        System.assert(resp.message.contains('valid Salesforce Id'), 'Should report the invalid Id: ' + resp.message);
    }

    @isTest
    static void invalidGiftCommitmentIdReturnsError() {
        AgentAction_FindGiftTransaction.Request r = new AgentAction_FindGiftTransaction.Request();
        r.giftCommitmentId = 'not-an-id';

        AgentAction_FindGiftTransaction.Response resp = run(r);

        System.assertEquals(false, resp.success);
        System.assert(resp.message.contains('valid Salesforce Id'), 'Should report the invalid Id: ' + resp.message);
    }

    @isTest
    static void disabledFlagReturnsError() {
        FeatureFlag.setOverride(AgentAction_FindGiftTransaction.ACTION_NAME, false);

        AgentAction_FindGiftTransaction.Response resp = run(req('gt', null));

        System.assertEquals(false, resp.success);
        System.assert(resp.message.contains('disabled'), 'Should report disabled: ' + resp.message);
    }

    @isTest
    static void unexpectedErrorReturnsSafeMessage() {
        AgentAction_FindGiftTransaction.service = new ThrowingService();

        AgentAction_FindGiftTransaction.Response resp = run(req('gt', null));

        System.assertEquals(false, resp.success);
        System.assertEquals('Something went wrong while searching gift transactions.', resp.message);
    }
}