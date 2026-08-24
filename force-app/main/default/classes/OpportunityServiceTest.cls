@isTest
private class OpportunityServiceTest {
  /** In-memory selector mock — no SOQL. */
  private class MockSelector implements IOpportunitySelector {
    private List<Opportunity> toReturn;
    private MockSelector(List<Opportunity> records) {
      this.toReturn = records;
    }
    public List<Opportunity> search(
      String searchTerm,
      Id accountId,
      String stage,
      Integer maxRecords
    ) {
      return toReturn;
    }
  }

  private static Opportunity opp(String id, String name) {
    return (Opportunity) JSON.deserialize(
      '{"Id":"' +
        id +
        '","Name":"' +
        name +
        '","StageName":"Prospecting","Amount":5000,' +
        '"CloseDate":"2026-01-01","Account":{"Name":"Acme Org"},"Owner":{"Name":"Jane Doe"}}',
      Opportunity.class
    );
  }

  @isTest
  static void mapsRecordsToSummaries() {
    OpportunityService svc = new OpportunityService();
    svc.selector = new MockSelector(
      new List<Opportunity>{ opp('006000000000001AAA', 'Solar Grant') }
    );

    List<OpportunitySummary> results = svc.findOpportunities(
      null,
      null,
      null,
      null
    );

    System.assertEquals(1, results.size());
    OpportunitySummary s = results[0];
    System.assertEquals('006000000000001AAA', s.id);
    System.assertEquals('Solar Grant', s.name);
    System.assertEquals('Prospecting', s.stage);
    System.assertEquals(5000, s.amount);
    System.assertEquals('Acme Org', s.accountName);
    System.assertEquals('Jane Doe', s.ownerName);
    System.assert(
      String.isNotBlank(s.formattedAmount),
      'formattedAmount should be set'
    );
    System.assertEquals('006000000000001AAA', s.id, 'record Id populated');
  }

  @isTest
  static void ranksByRelevanceWhenSearchTermGiven() {
    OpportunityService svc = new OpportunityService();
    svc.selector = new MockSelector(
      new List<Opportunity>{
        opp('006000000000001AAA', 'Alpha Grant'),
        opp('006000000000002AAA', 'Beta Fund')
      }
    );

    List<OpportunitySummary> results = svc.findOpportunities(
      'beta',
      null,
      null,
      10
    );

    System.assertEquals(2, results.size());
    System.assertEquals(
      'Beta Fund',
      results[0].name,
      'Best match should rank first'
    );
  }

  @isTest
  static void returnsEmptyWhenNoRecords() {
    OpportunityService svc = new OpportunityService();
    svc.selector = new MockSelector(new List<Opportunity>());

    List<OpportunitySummary> results = svc.findOpportunities(
      'anything',
      null,
      null,
      null
    );
    System.assertEquals(0, results.size());
  }
}