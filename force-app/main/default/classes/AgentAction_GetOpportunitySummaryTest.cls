@isTest
private class AgentAction_GetOpportunitySummaryTest {
  private class MockService implements IOpportunitySummaryService {
    private OpportunitySummaryResult toReturn;
    private MockService(OpportunitySummaryResult r) {
      this.toReturn = r;
    }
    public OpportunitySummaryResult getSummary(
      String searchTerm,
      Id opportunityId
    ) {
      return toReturn;
    }
  }

  private class ThrowingService implements IOpportunitySummaryService {
    public OpportunitySummaryResult getSummary(
      String searchTerm,
      Id opportunityId
    ) {
      throw new CalloutException('unexpected');
    }
  }

  private static AgentAction_GetOpportunitySummary.Response run(
    String name,
    String id
  ) {
    AgentAction_GetOpportunitySummary.Request r = new AgentAction_GetOpportunitySummary.Request();
    r.opportunityName = name;
    r.opportunityId = id;
    return AgentAction_GetOpportunitySummary.getOpportunitySummary(
      new List<AgentAction_GetOpportunitySummary.Request>{ r }
    )[0];
  }

  @isTest
  static void successReturnsSummaryText() {
    OpportunitySummaryResult res = new OpportunitySummaryResult();
    res.found = true;
    res.resultsText = 'Opportunity Summary: Test';
    res.record = new AgentRecordResult(
      (Id) '006000000000001AAA',
      'Opportunity',
      'Test'
    );
    AgentAction_GetOpportunitySummary.service = new MockService(res);

    AgentAction_GetOpportunitySummary.Response resp = run('Test', null);

    System.assertEquals(true, resp.success);
    System.assertEquals('Opportunity Summary: Test', resp.resultsText);
    System.assertEquals('006000000000001AAA', resp.record.recordId);
    System.assertEquals('Opportunity', resp.record.objectApiName);
    System.assertEquals('Test', resp.record.recordName);
  }

  @isTest
  static void notFoundReturnsFriendlyMessage() {
    OpportunitySummaryResult res = new OpportunitySummaryResult();
    res.found = false;
    AgentAction_GetOpportunitySummary.service = new MockService(res);

    AgentAction_GetOpportunitySummary.Response resp = run('nothing', null);
    System.assertEquals(true, resp.success);
    System.assertEquals('No matching opportunity was found.', resp.message);
  }

  @isTest
  static void missingInputReturnsError() {
    AgentAction_GetOpportunitySummary.Response resp = run(null, null);
    System.assertEquals(false, resp.success);
    System.assert(
      resp.message.contains('name or Id'),
      'asks for input: ' + resp.message
    );
  }

  @isTest
  static void invalidIdReturnsError() {
    AgentAction_GetOpportunitySummary.Response resp = run(null, 'not-an-id');
    System.assertEquals(false, resp.success);
    System.assert(
      resp.message.contains('valid Salesforce Id'),
      'reports invalid id: ' + resp.message
    );
  }

  @isTest
  static void disabledFlagReturnsError() {
    FeatureFlag.setOverride(
      AgentAction_GetOpportunitySummary.ACTION_NAME,
      false
    );
    AgentAction_GetOpportunitySummary.Response resp = run('Test', null);
    System.assertEquals(false, resp.success);
    System.assert(
      resp.message.contains('disabled'),
      'reports disabled: ' + resp.message
    );
  }

  @isTest
  static void unexpectedErrorReturnsSafeMessage() {
    AgentAction_GetOpportunitySummary.service = new ThrowingService();
    AgentAction_GetOpportunitySummary.Response resp = run('Test', null);
    System.assertEquals(false, resp.success);
    System.assertEquals(
      'Something went wrong while building the opportunity summary.',
      resp.message
    );
  }
}