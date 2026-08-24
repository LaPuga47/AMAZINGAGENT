@isTest
private class AgentAction_GetCampaignSummaryTest {
  private class MockService implements ICampaignSummaryService {
    private CampaignSummaryResult toReturn;
    private MockService(CampaignSummaryResult r) {
      this.toReturn = r;
    }
    public CampaignSummaryResult getSummary(String searchTerm, Id campaignId) {
      return toReturn;
    }
  }

  private class ThrowingService implements ICampaignSummaryService {
    public CampaignSummaryResult getSummary(String searchTerm, Id campaignId) {
      throw new CalloutException('unexpected');
    }
  }

  private static AgentAction_GetCampaignSummary.Response run(
    String name,
    String id
  ) {
    AgentAction_GetCampaignSummary.Request r = new AgentAction_GetCampaignSummary.Request();
    r.campaignName = name;
    r.campaignId = id;
    return AgentAction_GetCampaignSummary.getCampaignSummary(
      new List<AgentAction_GetCampaignSummary.Request>{ r }
    )[0];
  }

  @isTest
  static void successReturnsSummaryText() {
    CampaignSummaryResult res = new CampaignSummaryResult();
    res.found = true;
    res.resultsText = 'Campaign 360: Test';
    res.record = new AgentRecordResult(
      (Id) '701000000000001AAA',
      'Campaign',
      'Test'
    );
    AgentAction_GetCampaignSummary.service = new MockService(res);

    AgentAction_GetCampaignSummary.Response resp = run('Test', null);

    System.assertEquals(true, resp.success);
    System.assertEquals('Campaign 360: Test', resp.resultsText);
    System.assertEquals('701000000000001AAA', resp.record.recordId);
    System.assertEquals('Campaign', resp.record.objectApiName);
    System.assertEquals('Test', resp.record.recordName);
  }

  @isTest
  static void notFoundReturnsFriendlyMessage() {
    CampaignSummaryResult res = new CampaignSummaryResult();
    res.found = false;
    AgentAction_GetCampaignSummary.service = new MockService(res);

    AgentAction_GetCampaignSummary.Response resp = run('nothing', null);
    System.assertEquals(true, resp.success);
    System.assertEquals('No matching campaign was found.', resp.message);
  }

  @isTest
  static void missingInputReturnsError() {
    AgentAction_GetCampaignSummary.Response resp = run(null, null);
    System.assertEquals(false, resp.success);
    System.assert(
      resp.message.contains('name or Id'),
      'asks for input: ' + resp.message
    );
  }

  @isTest
  static void invalidIdReturnsError() {
    AgentAction_GetCampaignSummary.Response resp = run(null, 'not-an-id');
    System.assertEquals(false, resp.success);
    System.assert(
      resp.message.contains('valid Salesforce Id'),
      'reports invalid id: ' + resp.message
    );
  }

  @isTest
  static void disabledFlagReturnsError() {
    FeatureFlag.setOverride(AgentAction_GetCampaignSummary.ACTION_NAME, false);
    AgentAction_GetCampaignSummary.Response resp = run('Test', null);
    System.assertEquals(false, resp.success);
    System.assert(
      resp.message.contains('disabled'),
      'reports disabled: ' + resp.message
    );
  }

  @isTest
  static void unexpectedErrorReturnsSafeMessage() {
    AgentAction_GetCampaignSummary.service = new ThrowingService();
    AgentAction_GetCampaignSummary.Response resp = run('Test', null);
    System.assertEquals(false, resp.success);
    System.assertEquals(
      'Something went wrong while building the campaign summary.',
      resp.message
    );
  }
}