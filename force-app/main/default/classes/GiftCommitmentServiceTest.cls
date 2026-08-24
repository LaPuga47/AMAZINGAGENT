@isTest
private class GiftCommitmentServiceTest {
  private class MockSelector implements IGiftCommitmentSelector {
    private List<GiftCommitment> toReturn;
    private MockSelector(List<GiftCommitment> records) {
      this.toReturn = records;
    }
    public List<GiftCommitment> search(
      String searchTerm,
      Id donorId,
      String status,
      Integer maxRecords
    ) {
      return toReturn;
    }
  }

  private static GiftCommitment gc(String id, String name) {
    return (GiftCommitment) JSON.deserialize(
      '{"Id":"' +
        id +
        '","Name":"' +
        name +
        '","Status":"Active",' +
        '"ExpectedTotalCmtAmount":100000,"TotalPaidTransactionAmount":40000,' +
        '"Remaining_Balance__c":60000,"NextTransactionDate":"2026-09-01",' +
        '"NextTransactionAmount":20000,"EffectiveStartDate":"2026-01-01",' +
        '"ExpectedEndDate":"2028-12-31","Donor":{"Name":"Gates Foundation"}}',
      GiftCommitment.class
    );
  }

  @isTest
  static void mapsRecordsToSummaries() {
    GiftCommitmentService svc = new GiftCommitmentService();
    svc.selector = new MockSelector(
      new List<GiftCommitment>{ gc('6gc000000000001AAA', 'Multi-Year Pledge') }
    );

    List<GiftCommitmentSummary> results = svc.findGiftCommitments(
      null,
      null,
      null,
      null
    );

    System.assertEquals(1, results.size());
    GiftCommitmentSummary s = results[0];
    System.assertEquals('Multi-Year Pledge', s.name);
    System.assertEquals('Active', s.status);
    System.assertEquals('Gates Foundation', s.donorName);
    System.assertEquals(100000, s.expectedTotalAmount);
    System.assertEquals(60000, s.remainingBalance);
    System.assertEquals(
      null,
      s.ownerName,
      'Owner is polymorphic (Group,User) and not set in this mock'
    );
    System.assert(
      String.isNotBlank(s.formattedExpectedTotal),
      'formattedExpectedTotal should be set'
    );
    System.assertEquals('6gc000000000001AAA', s.id, 'record Id populated');
  }

  @isTest
  static void ranksByRelevanceWhenSearchTermGiven() {
    GiftCommitmentService svc = new GiftCommitmentService();
    svc.selector = new MockSelector(
      new List<GiftCommitment>{
        gc('6gc000000000001AAA', 'Alpha Pledge'),
        gc('6gc000000000002AAA', 'Beta Pledge')
      }
    );

    List<GiftCommitmentSummary> results = svc.findGiftCommitments(
      'beta',
      null,
      null,
      10
    );

    System.assertEquals(2, results.size());
    System.assertEquals(
      'Beta Pledge',
      results[0].name,
      'Best match should rank first'
    );
  }

  @isTest
  static void returnsEmptyWhenNoRecords() {
    GiftCommitmentService svc = new GiftCommitmentService();
    svc.selector = new MockSelector(new List<GiftCommitment>());

    List<GiftCommitmentSummary> results = svc.findGiftCommitments(
      'anything',
      null,
      null,
      null
    );
    System.assertEquals(0, results.size());
  }
}