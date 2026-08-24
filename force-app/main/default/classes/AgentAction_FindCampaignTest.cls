@isTest
private class AgentAction_FindCampaignTest {
    private class MockService implements ICampaignService {
        private List<CampaignSummary> toReturn;
        private MockService(List<CampaignSummary> summaries) {
            this.toReturn = summaries;
        }
        public List<CampaignSummary> findCampaigns(String t, String status, Integer m) {
            return toReturn;
        }
    }

    private class ThrowingService implements ICampaignService {
        public List<CampaignSummary> findCampaigns(String t, String status, Integer m) {
            throw new CalloutException('unexpected');
        }
    }

    private static AgentAction_FindCampaign.Request req(String term) {
        AgentAction_FindCampaign.Request r = new AgentAction_FindCampaign.Request();
        r.searchTerm = term;
        return r;
    }

    private static AgentAction_FindCampaign.Response run(AgentAction_FindCampaign.Request r) {
        return AgentAction_FindCampaign.findCampaign(new List<AgentAction_FindCampaign.Request>{ r })[0];
    }

    @isTest
    static void successPathReturnsResults() {
        CampaignSummary s = new CampaignSummary();
        s.id = '701000000000001AAA';
        s.name = 'Year-End Appeal';
        AgentAction_FindCampaign.service = new MockService(new List<CampaignSummary>{ s });

        AgentAction_FindCampaign.Response resp = run(req('year'));

        System.assertEquals(true, resp.success);
        System.assertEquals(1, resp.count);
        System.assertEquals(1, resp.campaigns.size());
        System.assert(resp.message.contains('1'), 'Message should reflect the count');
    }

    @isTest
    static void emptyPathReturnsFriendlyMessage() {
        AgentAction_FindCampaign.service = new MockService(new List<CampaignSummary>());

        AgentAction_FindCampaign.Response resp = run(req('nothing'));

        System.assertEquals(true, resp.success);
        System.assertEquals(0, resp.count);
        System.assertEquals('No campaigns matched your search.', resp.message);
        System.assertEquals(0, resp.campaigns.size());
    }

    @isTest
    static void disabledFlagReturnsError() {
        FeatureFlag.setOverride(AgentAction_FindCampaign.ACTION_NAME, false);

        AgentAction_FindCampaign.Response resp = run(req('year'));

        System.assertEquals(false, resp.success);
        System.assert(resp.message.contains('disabled'), 'Should report disabled: ' + resp.message);
    }

    @isTest
    static void unexpectedErrorReturnsSafeMessage() {
        AgentAction_FindCampaign.service = new ThrowingService();

        AgentAction_FindCampaign.Response resp = run(req('year'));

        System.assertEquals(false, resp.success);
        System.assertEquals('Something went wrong while searching campaigns.', resp.message);
    }
}