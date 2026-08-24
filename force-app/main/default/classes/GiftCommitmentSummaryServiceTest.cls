@isTest
private class GiftCommitmentSummaryServiceTest {
  private class MockSelector implements IGiftCommitmentSummarySelector {
    private GiftCommitmentSummaryData data;
    private MockSelector(GiftCommitmentSummaryData data) {
      this.data = data;
    }
    public GiftCommitmentSummaryData fetch(String searchTerm, Id commitmentId) {
      return data;
    }
  }

  private static GiftCommitmentSummaryData sampleData() {
    GiftCommitmentSummaryData d = new GiftCommitmentSummaryData();
    d.commitment = (GiftCommitment) JSON.deserialize(
      '{"Id":"6gc000000000001AAA","Name":"Gates Multi-Year Pledge","Status":"Active",' +
        '"ExpectedTotalCmtAmount":300000,"TotalPaidTransactionAmount":100000,"Remaining_Balance__c":200000,' +
        '"EffectiveStartDate":"2026-01-01","ExpectedEndDate":"2028-12-31","NextTransactionDate":"2026-09-01",' +
        '"NextTransactionAmount":100000,"RecurrenceType":"Annual","ScheduleType":"Fixed","CurrencyIsoCode":"USD",' +
        '"OpportunityId":"006000000000001AAA","CampaignId":"701000000000001AAA",' +
        '"Donor":{"Name":"Gates Foundation"},"Opportunity":{"Name":"Gates 2026 Grant"},"Campaign":{"Name":"Year-End"}}',
      GiftCommitment.class
    );
    d.transactions.add(
      (GiftTransaction) JSON.deserialize(
        '{"Id":"6tr000000000001AAA","Name":"GT-1","Status":"Paid","CurrentAmount":100000,"TransactionDate":"2026-02-01"}',
        GiftTransaction.class
      )
    );
    d.transactions.add(
      (GiftTransaction) JSON.deserialize(
        '{"Id":"6tr000000000002AAA","Name":"GT-2","Status":"Pending","CurrentAmount":100000,"TransactionDate":"2026-09-01"}',
        GiftTransaction.class
      )
    );
    d.restrictions.add(
      (Restriction__c) JSON.deserialize(
        '{"Id":"a0L000000000001AAA","Name":"R2025-1","Restriction_Country__c":"Kenya","x2026_Funds_Allocated__c":200000}',
        Restriction__c.class
      )
    );
    return d;
  }

  @isTest
  static void buildsGroundedCommitmentSummary() {
    GiftCommitmentSummaryService svc = new GiftCommitmentSummaryService();
    svc.selector = new MockSelector(sampleData());

    GiftCommitmentSummaryResult r = svc.getSummary('Gates', null);

    System.assertEquals(true, r.found);
    System.assertEquals('Gates Multi-Year Pledge', r.commitmentName);
    String t = r.resultsText;
    System.assert(
      t.contains('Gift Commitment 360: Gates Multi-Year Pledge'),
      'header'
    );
    System.assert(t.contains('Donor: Gates Foundation'), 'donor');
    System.assert(
      t.contains('Opportunity: Gates 2026 Grant'),
      'opportunity link'
    );
    System.assert(t.contains('Expected Total: USD 300,000'), 'expected');
    // Only the Paid 100,000 counts as received; Pending excluded.
    System.assert(
      t.contains(
        'Confirmed Received (Paid transactions, computed): USD 100,000'
      ),
      'received: ' + t
    );
    System.assert(
      t.contains('Outstanding (Expected - Received, computed): USD 200,000'),
      'outstanding: ' + t
    );
    System.assert(t.contains('Recurrence: Annual'), 'schedule');
    System.assert(
      t.contains('Gift Transactions (count): 2 (Paid: 1)'),
      'txn counts'
    );
    System.assert(t.contains('Paid: 1 (USD 100,000)'), 'paid breakdown: ' + t);
    System.assert(t.contains('Pending: 1 (USD 100,000)'), 'pending breakdown');
    System.assert(
      t.contains('Average Gift (Paid): USD 100,000'),
      'average gift'
    );
    // v2 finance rules: expected 300,000 vs allocated 200,000 -> under-allocated.
    System.assert(
      t.contains('Total Restriction Allocated: USD 200,000'),
      'restriction allocated: ' + t
    );
    System.assert(
      t.contains('Restriction Status: Under-allocated'),
      'under-allocated: ' + t
    );
  }

  @isTest
  static void notFoundReturnsFoundFalse() {
    GiftCommitmentSummaryService svc = new GiftCommitmentSummaryService();
    svc.selector = new MockSelector(new GiftCommitmentSummaryData());

    GiftCommitmentSummaryResult r = svc.getSummary('nope', null);
    System.assertEquals(false, r.found);
  }

  @isTest
  static void handlesNoRelatedRecords() {
    GiftCommitmentSummaryData d = new GiftCommitmentSummaryData();
    d.commitment = (GiftCommitment) JSON.deserialize(
      '{"Id":"6gc000000000009AAA","Name":"Bare Pledge","ExpectedTotalCmtAmount":5000,"CurrencyIsoCode":"USD"}',
      GiftCommitment.class
    );
    GiftCommitmentSummaryService svc = new GiftCommitmentSummaryService();
    svc.selector = new MockSelector(d);

    GiftCommitmentSummaryResult r = svc.getSummary(null, '6gc000000000009AAA');
    System.assertEquals(true, r.found);
    System.assert(
      r.resultsText.contains(
        'Confirmed Received (Paid transactions, computed): USD 0'
      ),
      'zero received'
    );
    System.assert(
      r.resultsText.contains(
        'Outstanding (Expected - Received, computed): USD 5,000'
      ),
      'full outstanding'
    );
    System.assert(
      r.resultsText.contains('Gift Transactions (count): 0 (Paid: 0)'),
      'no txns'
    );
  }

  @isTest
  static void recordRefPopulatedAndTextClean() {
    GiftCommitmentSummaryService svc = new GiftCommitmentSummaryService();
    svc.selector = new MockSelector(sampleData());
    GiftCommitmentSummaryResult r = svc.getSummary('x', null);
    System.assertNotEquals(null, r.record, 'record ref present');
    System.assertEquals(
      'GiftCommitment',
      r.record.objectApiName,
      'object api name'
    );
    System.assert(String.isNotBlank(r.record.recordId), 'record id populated');
    System.assert(
      String.isNotBlank(r.record.recordName),
      'record name populated'
    );
    String t = r.resultsText;
    System.assert(!t.containsIgnoreCase('http'), 'no url in resultsText');
    System.assert(!t.contains('URL_Redacted'), 'no redacted token');
    System.assert(
      !t.contains('6gc000000000001AAA'),
      'no raw record id in resultsText'
    );
  }
}