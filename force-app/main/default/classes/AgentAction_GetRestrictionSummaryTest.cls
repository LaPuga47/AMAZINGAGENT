@isTest
private class AgentAction_GetRestrictionSummaryTest {
  private class MockService implements IRestrictionSummaryService {
    private RestrictionSummaryResult toReturn;
    private MockService(RestrictionSummaryResult r) {
      this.toReturn = r;
    }
    public RestrictionSummaryResult getSummary(
      String searchTerm,
      Id restrictionId
    ) {
      return toReturn;
    }
  }

  private class ThrowingService implements IRestrictionSummaryService {
    public RestrictionSummaryResult getSummary(
      String searchTerm,
      Id restrictionId
    ) {
      throw new CalloutException('unexpected');
    }
  }

  private static AgentAction_GetRestrictionSummary.Response run(
    String name,
    String id
  ) {
    AgentAction_GetRestrictionSummary.Request r = new AgentAction_GetRestrictionSummary.Request();
    r.restrictionName = name;
    r.restrictionId = id;
    return AgentAction_GetRestrictionSummary.getRestrictionSummary(
      new List<AgentAction_GetRestrictionSummary.Request>{ r }
    )[0];
  }

  @isTest
  static void successReturnsSummaryText() {
    RestrictionSummaryResult res = new RestrictionSummaryResult();
    res.found = true;
    res.resultsText = 'Restriction 360: Test';
    res.record = new AgentRecordResult(
      (Id) 'a0L000000000001AAA',
      'Restriction__c',
      'Test'
    );
    AgentAction_GetRestrictionSummary.service = new MockService(res);

    AgentAction_GetRestrictionSummary.Response resp = run('Test', null);

    System.assertEquals(true, resp.success);
    System.assertEquals('Restriction 360: Test', resp.resultsText);
    System.assertEquals('a0L000000000001AAA', resp.record.recordId);
    System.assertEquals('Restriction__c', resp.record.objectApiName);
    System.assertEquals('Test', resp.record.recordName);
  }

  @isTest
  static void notFoundReturnsFriendlyMessage() {
    RestrictionSummaryResult res = new RestrictionSummaryResult();
    res.found = false;
    AgentAction_GetRestrictionSummary.service = new MockService(res);

    AgentAction_GetRestrictionSummary.Response resp = run('nothing', null);
    System.assertEquals(true, resp.success);
    System.assertEquals('No matching restriction was found.', resp.message);
  }

  @isTest
  static void missingInputReturnsError() {
    AgentAction_GetRestrictionSummary.Response resp = run(null, null);
    System.assertEquals(false, resp.success);
    System.assert(
      resp.message.contains('name or Id'),
      'asks for input: ' + resp.message
    );
  }

  @isTest
  static void invalidIdReturnsError() {
    AgentAction_GetRestrictionSummary.Response resp = run(null, 'not-an-id');
    System.assertEquals(false, resp.success);
    System.assert(
      resp.message.contains('valid Salesforce Id'),
      'reports invalid id: ' + resp.message
    );
  }

  @isTest
  static void disabledFlagReturnsError() {
    FeatureFlag.setOverride(
      AgentAction_GetRestrictionSummary.ACTION_NAME,
      false
    );
    AgentAction_GetRestrictionSummary.Response resp = run('Test', null);
    System.assertEquals(false, resp.success);
    System.assert(
      resp.message.contains('disabled'),
      'reports disabled: ' + resp.message
    );
  }

  @isTest
  static void unexpectedErrorReturnsSafeMessage() {
    AgentAction_GetRestrictionSummary.service = new ThrowingService();
    AgentAction_GetRestrictionSummary.Response resp = run('Test', null);
    System.assertEquals(false, resp.success);
    System.assertEquals(
      'Something went wrong while building the restriction summary.',
      resp.message
    );
  }
}