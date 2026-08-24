@isTest
private class AccountServiceTest {
  private class MockSelector implements IAccountSelector {
    private List<Account> toReturn;
    private MockSelector(List<Account> records) {
      this.toReturn = records;
    }
    public List<Account> search(
      String searchTerm,
      String accountType,
      Integer maxRecords
    ) {
      return toReturn;
    }
  }

  private static Account acct(String id, String name) {
    return (Account) JSON.deserialize(
      '{"Id":"' +
        id +
        '","Name":"' +
        name +
        '","Type":"Foundation","Industry":"Nonprofit",' +
        '"Phone":"555-0100","Website":"https://example.org","BillingCity":"Kigali",' +
        '"BillingCountry":"Rwanda","Owner":{"Name":"Jane Doe"}}',
      Account.class
    );
  }

  @isTest
  static void mapsRecordsToSummaries() {
    AccountService svc = new AccountService();
    svc.selector = new MockSelector(
      new List<Account>{ acct('001000000000001AAA', 'Gates Foundation') }
    );

    List<AccountSummary> results = svc.findAccounts(null, null, null);

    System.assertEquals(1, results.size());
    AccountSummary s = results[0];
    System.assertEquals('001000000000001AAA', s.id);
    System.assertEquals('Gates Foundation', s.name);
    System.assertEquals('Foundation', s.type);
    System.assertEquals('Nonprofit', s.industry);
    System.assertEquals('Kigali', s.city);
    System.assertEquals('Rwanda', s.country);
    System.assertEquals('Jane Doe', s.ownerName);
    System.assertEquals('001000000000001AAA', s.id, 'record Id populated');
  }

  @isTest
  static void ranksByRelevanceWhenSearchTermGiven() {
    AccountService svc = new AccountService();
    svc.selector = new MockSelector(
      new List<Account>{
        acct('001000000000001AAA', 'Alpha Trust'),
        acct('001000000000002AAA', 'Beta Foundation')
      }
    );

    List<AccountSummary> results = svc.findAccounts('beta', null, 10);

    System.assertEquals(2, results.size());
    System.assertEquals(
      'Beta Foundation',
      results[0].name,
      'Best match should rank first'
    );
  }

  @isTest
  static void returnsEmptyWhenNoRecords() {
    AccountService svc = new AccountService();
    svc.selector = new MockSelector(new List<Account>());

    List<AccountSummary> results = svc.findAccounts('anything', null, null);
    System.assertEquals(0, results.size());
  }
}