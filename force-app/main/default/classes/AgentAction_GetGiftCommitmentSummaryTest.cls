@isTest
private class AgentAction_GetGiftCommitmentSummaryTest {
  private class MockService implements IGiftCommitmentSummaryService {
    private GiftCommitmentSummaryResult toReturn;
    private MockService(GiftCommitmentSummaryResult r) {
      this.toReturn = r;
    }
    public GiftCommitmentSummaryResult getSummary(
      String searchTerm,
      Id commitmentId
    ) {
      return toReturn;
    }
  }

  private class ThrowingService implements IGiftCommitmentSummaryService {
    public GiftCommitmentSummaryResult getSummary(
      String searchTerm,
      Id commitmentId
    ) {
      throw new CalloutException('unexpected');
    }
  }

  private static AgentAction_GetGiftCommitmentSummary.Response run(
    String name,
    String id
  ) {
    AgentAction_GetGiftCommitmentSummary.Request r = new AgentAction_GetGiftCommitmentSummary.Request();
    r.giftCommitmentName = name;
    r.giftCommitmentId = id;
    return AgentAction_GetGiftCommitmentSummary.getGiftCommitmentSummary(
      new List<AgentAction_GetGiftCommitmentSummary.Request>{ r }
    )[0];
  }

  @isTest
  static void successReturnsSummaryText() {
    GiftCommitmentSummaryResult res = new GiftCommitmentSummaryResult();
    res.found = true;
    res.resultsText = 'Gift Commitment 360: Test';
    res.record = new AgentRecordResult(
      (Id) '6gc000000000001AAA',
      'GiftCommitment',
      'Test'
    );
    AgentAction_GetGiftCommitmentSummary.service = new MockService(res);

    AgentAction_GetGiftCommitmentSummary.Response resp = run('Test', null);

    System.assertEquals(true, resp.success);
    System.assertEquals('Gift Commitment 360: Test', resp.resultsText);
    System.assertEquals('6gc000000000001AAA', resp.record.recordId);
    System.assertEquals('GiftCommitment', resp.record.objectApiName);
    System.assertEquals('Test', resp.record.recordName);
  }

  @isTest
  static void notFoundReturnsFriendlyMessage() {
    GiftCommitmentSummaryResult res = new GiftCommitmentSummaryResult();
    res.found = false;
    AgentAction_GetGiftCommitmentSummary.service = new MockService(res);

    AgentAction_GetGiftCommitmentSummary.Response resp = run('nothing', null);
    System.assertEquals(true, resp.success);
    System.assertEquals('No matching gift commitment was found.', resp.message);
  }

  @isTest
  static void missingInputReturnsError() {
    AgentAction_GetGiftCommitmentSummary.Response resp = run(null, null);
    System.assertEquals(false, resp.success);
    System.assert(
      resp.message.contains('name or Id'),
      'asks for input: ' + resp.message
    );
  }

  @isTest
  static void invalidIdReturnsError() {
    AgentAction_GetGiftCommitmentSummary.Response resp = run(null, 'not-an-id');
    System.assertEquals(false, resp.success);
    System.assert(
      resp.message.contains('valid Salesforce Id'),
      'reports invalid id: ' + resp.message
    );
  }

  @isTest
  static void disabledFlagReturnsError() {
    FeatureFlag.setOverride(
      AgentAction_GetGiftCommitmentSummary.ACTION_NAME,
      false
    );
    AgentAction_GetGiftCommitmentSummary.Response resp = run('Test', null);
    System.assertEquals(false, resp.success);
    System.assert(
      resp.message.contains('disabled'),
      'reports disabled: ' + resp.message
    );
  }

  @isTest
  static void unexpectedErrorReturnsSafeMessage() {
    AgentAction_GetGiftCommitmentSummary.service = new ThrowingService();
    AgentAction_GetGiftCommitmentSummary.Response resp = run('Test', null);
    System.assertEquals(false, resp.success);
    System.assertEquals(
      'Something went wrong while building the gift commitment summary.',
      resp.message
    );
  }
}