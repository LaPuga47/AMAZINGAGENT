@isTest
private class OpportunitySummaryServiceTest {
  private class MockSelector implements IOpportunitySummarySelector {
    private OpportunitySummaryData data;
    private MockSelector(OpportunitySummaryData data) {
      this.data = data;
    }
    public OpportunitySummaryData fetch(String searchTerm, Id opportunityId) {
      return data;
    }
  }

  private static OpportunitySummaryData sampleData() {
    OpportunitySummaryData d = new OpportunitySummaryData();
    d.opp = (Opportunity) JSON.deserialize(
      '{"Id":"006000000000001AAA","Name":"Agency Fund 2027-2028 Technology","StageName":"Proposal / Negotiation",' +
        '"Amount":250000,"Probability":70,"CloseDate":"2027-06-30","CurrencyIsoCode":"USD",' +
        '"Account":{"Name":"Agency Fund"},"Owner":{"Name":"Grant Manager"}}',
      Opportunity.class
    );
    d.commitments.add(
      (GiftCommitment) JSON.deserialize(
        '{"Id":"6gc000000000001AAA","Name":"Agency Fund 2027-2028 Technology","Status":"Active","ExpectedTotalCmtAmount":250000}',
        GiftCommitment.class
      )
    );
    d.transactions.add(
      (GiftTransaction) JSON.deserialize(
        '{"Id":"6tr000000000001AAA","Name":"GT-1","Status":"Paid","CurrentAmount":100000,"TransactionDate":"2027-01-15"}',
        GiftTransaction.class
      )
    );
    d.transactions.add(
      (GiftTransaction) JSON.deserialize(
        '{"Id":"6tr000000000002AAA","Name":"GT-2","Status":"Pending","CurrentAmount":50000,"TransactionDate":"2027-03-15"}',
        GiftTransaction.class
      )
    );
    d.restrictions.add(
      (Restriction__c) JSON.deserialize(
        '{"Id":"a0L000000000001AAA","Name":"R2025-21992","Restriction_Country__c":"Rwanda","x2027_Funds_Allocated__c":250000}',
        Restriction__c.class
      )
    );
    return d;
  }

  @isTest
  static void buildsGroundedSummaryWithComputedTotals() {
    OpportunitySummaryService svc = new OpportunitySummaryService();
    svc.selector = new MockSelector(sampleData());

    OpportunitySummaryResult r = svc.getSummary('Agency Fund', null);

    System.assertEquals(true, r.found);
    System.assertEquals('Agency Fund 2027-2028 Technology', r.opportunityName);
    String t = r.resultsText;
    System.assert(
      t.contains('Opportunity Summary: Agency Fund 2027-2028 Technology'),
      'has header'
    );
    System.assert(t.contains('Account: Agency Fund'), 'has account');
    System.assert(t.contains('Probability: 70'), 'has probability');
    System.assert(
      t.contains('Gift Transactions Found: 2'),
      'counts all transactions'
    );
    // Only the Paid 100,000 counts as received; Pending 50,000 excluded.
    System.assert(
      t.contains('Confirmed Received (Paid): USD 100,000'),
      'received = paid only: ' + t
    );
    System.assert(t.contains('Paid: 1 (USD 100,000)'), 'paid breakdown: ' + t);
    System.assert(t.contains('Pending: 1 (USD 50,000)'), 'pending breakdown');
    System.assert(
      t.contains('Average Gift (Paid): USD 100,000'),
      'average gift'
    );
    // Outstanding = 250,000 expected - 100,000 received = 150,000
    System.assert(
      t.contains('Outstanding / Expected Amount: USD 150,000'),
      'outstanding computed: ' + t
    );
    System.assert(t.contains('R2025-21992'), 'lists restriction');
    // v2 finance rules: restriction allocation reconciled against the commitment expected total.
    System.assert(
      t.contains('Total Restriction Allocated: USD 250,000'),
      'restriction allocated: ' + t
    );
    System.assert(t.contains('Restriction Status: In sync'), 'in sync: ' + t);
  }

  @isTest
  static void notFoundReturnsFoundFalse() {
    OpportunitySummaryService svc = new OpportunitySummaryService();
    svc.selector = new MockSelector(new OpportunitySummaryData());

    OpportunitySummaryResult r = svc.getSummary('nothing', null);
    System.assertEquals(false, r.found);
  }

  @isTest
  static void handlesNoRelatedRecords() {
    OpportunitySummaryData d = new OpportunitySummaryData();
    d.opp = (Opportunity) JSON.deserialize(
      '{"Id":"006000000000009AAA","Name":"Lonely Opp","StageName":"Prospecting","Amount":1000,"CurrencyIsoCode":"USD"}',
      Opportunity.class
    );
    OpportunitySummaryService svc = new OpportunitySummaryService();
    svc.selector = new MockSelector(d);

    OpportunitySummaryResult r = svc.getSummary(null, '006000000000009AAA');
    System.assertEquals(true, r.found);
    System.assert(
      r.resultsText.contains('Gift Commitment: None linked'),
      'notes no commitment'
    );
    System.assert(
      r.resultsText.contains('Confirmed Received (Paid): USD 0'),
      'received defaults to 0'
    );
    System.assert(
      r.resultsText.contains('Outstanding / Expected Amount: USD 1,000'),
      'outstanding = full amount'
    );
  }

  @isTest
  static void recordRefPopulatedAndTextClean() {
    OpportunitySummaryService svc = new OpportunitySummaryService();
    svc.selector = new MockSelector(sampleData());
    OpportunitySummaryResult r = svc.getSummary('x', null);
    System.assertNotEquals(null, r.record, 'record ref present');
    System.assertEquals(
      'Opportunity',
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
      !t.contains('006000000000001AAA'),
      'no raw record id in resultsText'
    );
  }
}