@isTest
private class GiftTransactionServiceTest {
  private class MockSelector implements IGiftTransactionSelector {
    private List<GiftTransaction> toReturn;
    private MockSelector(List<GiftTransaction> records) {
      this.toReturn = records;
    }
    public List<GiftTransaction> search(
      String t,
      Id donorId,
      Id gcId,
      Id campaignId,
      String status,
      Integer maxRecords
    ) {
      return toReturn;
    }
  }

  // NOTE: Owner is omitted — GiftTransaction.OwnerId is polymorphic (Group,User)
  // and cannot be represented in JSON-deserialized mocks.
  private static GiftTransaction gt(String id, String name) {
    return (GiftTransaction) JSON.deserialize(
      '{"Id":"' +
        id +
        '","Name":"' +
        name +
        '","Status":"Paid","TransactionDate":"2026-03-15",' +
        '"OriginalAmount":25000,"CurrentAmount":25000,"PaymentMethod":"Check","GiftType":"Cash",' +
        '"Donor":{"Name":"Gates Foundation"},"GiftCommitment":{"Name":"Multi-Year Pledge"},' +
        '"Campaign":{"Name":"Year-End Appeal"}}',
      GiftTransaction.class
    );
  }

  @isTest
  static void mapsRecordsToSummaries() {
    GiftTransactionService svc = new GiftTransactionService();
    svc.selector = new MockSelector(
      new List<GiftTransaction>{ gt('6tr000000000001AAA', 'GT-0001') }
    );

    List<GiftTransactionSummary> results = svc.findGiftTransactions(
      null,
      null,
      null,
      null,
      null,
      null
    );

    System.assertEquals(1, results.size());
    GiftTransactionSummary s = results[0];
    System.assertEquals('GT-0001', s.name);
    System.assertEquals('Paid', s.status);
    System.assertEquals(25000, s.currentAmount);
    System.assertEquals('Check', s.paymentMethod);
    System.assertEquals('Gates Foundation', s.donorName);
    System.assertEquals('Multi-Year Pledge', s.giftCommitmentName);
    System.assertEquals('Year-End Appeal', s.campaignName);
    System.assert(
      String.isNotBlank(s.formattedAmount),
      'formattedAmount should be set'
    );
    System.assertEquals(
      'GiftTransaction',
      s.record.objectApiName,
      'record populated'
    );
    System.assertEquals('6tr000000000001AAA', s.record.recordId, 'record id');
  }

  @isTest
  static void ranksByRelevanceWhenSearchTermGiven() {
    GiftTransactionService svc = new GiftTransactionService();
    svc.selector = new MockSelector(
      new List<GiftTransaction>{
        gt('6tr000000000001AAA', 'Alpha Gift'),
        gt('6tr000000000002AAA', 'Beta Gift')
      }
    );

    List<GiftTransactionSummary> results = svc.findGiftTransactions(
      'beta',
      null,
      null,
      null,
      null,
      10
    );

    System.assertEquals(2, results.size());
    System.assertEquals(
      'Beta Gift',
      results[0].name,
      'Best match should rank first'
    );
  }

  @isTest
  static void returnsEmptyWhenNoRecords() {
    GiftTransactionService svc = new GiftTransactionService();
    svc.selector = new MockSelector(new List<GiftTransaction>());

    List<GiftTransactionSummary> results = svc.findGiftTransactions(
      'anything',
      null,
      null,
      null,
      null,
      null
    );
    System.assertEquals(0, results.size());
  }
}