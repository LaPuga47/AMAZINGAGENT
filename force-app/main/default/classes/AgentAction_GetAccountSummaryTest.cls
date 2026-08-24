@isTest
private class AgentAction_GetAccountSummaryTest {
  private class MockService implements IAccountSummaryService {
    private AccountSummaryResult toReturn;
    private MockService(AccountSummaryResult r) {
      this.toReturn = r;
    }
    public AccountSummaryResult getSummary(String searchTerm, Id accountId) {
      return toReturn;
    }
  }

  private class ThrowingService implements IAccountSummaryService {
    public AccountSummaryResult getSummary(String searchTerm, Id accountId) {
      throw new CalloutException('unexpected');
    }
  }

  private static AgentAction_GetAccountSummary.Response run(
    String name,
    String id
  ) {
    AgentAction_GetAccountSummary.Request r = new AgentAction_GetAccountSummary.Request();
    r.accountName = name;
    r.accountId = id;
    return AgentAction_GetAccountSummary.getAccountSummary(
      new List<AgentAction_GetAccountSummary.Request>{ r }
    )[0];
  }

  @isTest
  static void successReturnsSummaryText() {
    AccountSummaryResult res = new AccountSummaryResult();
    res.found = true;
    res.resultsText = 'Account 360: Test';
    res.record = new AgentRecordResult(
      (Id) '001000000000001AAA',
      'Account',
      'Test'
    );
    AgentAction_GetAccountSummary.service = new MockService(res);

    AgentAction_GetAccountSummary.Response resp = run('Test', null);

    System.assertEquals(true, resp.success);
    System.assertEquals('Account 360: Test', resp.resultsText);
    System.assertEquals('001000000000001AAA', resp.record.recordId);
    System.assertEquals('Account', resp.record.objectApiName);
    System.assertEquals('Test', resp.record.recordName);
  }

  @isTest
  static void notFoundReturnsFriendlyMessage() {
    AccountSummaryResult res = new AccountSummaryResult();
    res.found = false;
    AgentAction_GetAccountSummary.service = new MockService(res);

    AgentAction_GetAccountSummary.Response resp = run('nothing', null);
    System.assertEquals(true, resp.success);
    System.assertEquals('No matching account was found.', resp.message);
  }

  @isTest
  static void missingInputReturnsError() {
    AgentAction_GetAccountSummary.Response resp = run(null, null);
    System.assertEquals(false, resp.success);
    System.assert(
      resp.message.contains('name or Id'),
      'asks for input: ' + resp.message
    );
  }

  @isTest
  static void invalidIdReturnsError() {
    AgentAction_GetAccountSummary.Response resp = run(null, 'not-an-id');
    System.assertEquals(false, resp.success);
    System.assert(
      resp.message.contains('valid Salesforce Id'),
      'reports invalid id: ' + resp.message
    );
  }

  @isTest
  static void disabledFlagReturnsError() {
    FeatureFlag.setOverride(AgentAction_GetAccountSummary.ACTION_NAME, false);
    AgentAction_GetAccountSummary.Response resp = run('Test', null);
    System.assertEquals(false, resp.success);
    System.assert(
      resp.message.contains('disabled'),
      'reports disabled: ' + resp.message
    );
  }

  @isTest
  static void unexpectedErrorReturnsSafeMessage() {
    AgentAction_GetAccountSummary.service = new ThrowingService();
    AgentAction_GetAccountSummary.Response resp = run('Test', null);
    System.assertEquals(false, resp.success);
    System.assertEquals(
      'Something went wrong while building the account summary.',
      resp.message
    );
  }
}