@isTest
private class CampaignSummaryServiceTest {
  private class MockSelector implements ICampaignSummarySelector {
    private CampaignSummaryData data;
    private MockSelector(CampaignSummaryData data) {
      this.data = data;
    }
    public CampaignSummaryData fetch(String searchTerm, Id campaignId) {
      return data;
    }
  }

  private static CampaignSummaryData sampleData() {
    CampaignSummaryData d = new CampaignSummaryData();
    d.camp = (Campaign) JSON.deserialize(
      '{"Id":"701000000000001AAA","Name":"Year-End Appeal","Type":"Fundraising","Status":"In Progress",' +
        '"IsActive":true,"StartDate":"2026-01-01","EndDate":"2026-12-31","CurrencyIsoCode":"USD",' +
        '"NumberOfOpportunities":10,"NumberOfWonOpportunities":4,"AmountAllOpportunities":500000,' +
        '"AmountWonOpportunities":200000,"NumberOfContacts":50,"NumberOfResponses":30,' +
        '"ActualCost":50000,"BudgetedCost":60000,"ExpectedRevenue":300000,"Owner":{"Name":"Jane Doe"}}',
      Campaign.class
    );
    d.openPipelineAmount = 300000;
    d.openOpportunityCount = 6;
    d.giftCountByStatus.put('Paid', 1);
    d.giftCountByStatus.put('Pending', 1);
    d.giftAmountByStatus.put('Paid', 25000);
    d.giftAmountByStatus.put('Pending', 10000);
    d.giftReceivedAmount = 25000;
    d.paidGiftTransactionCount = 1;
    d.totalGiftTransactionCount = 2;
    d.memberCount = 50;
    d.respondedMemberCount = 20;
    d.memberStatusCounts.put('Sent', 30);
    d.memberStatusCounts.put('Responded', 20);
    return d;
  }

  @isTest
  static void buildsExecutiveSummary() {
    CampaignSummaryService svc = new CampaignSummaryService();
    svc.selector = new MockSelector(sampleData());

    CampaignSummaryResult r = svc.getSummary('Year-End', null);

    System.assertEquals(true, r.found);
    String t = r.resultsText;
    // Plain headings only — no markdown symbols (the agent UI shows them literally).
    System.assert(!t.contains('**'), 'no bold markdown: ' + t);
    System.assert(!t.contains('## '), 'no heading markdown');
    System.assert(t.contains('CAMPAIGN OVERVIEW'), 'overview heading');
    System.assert(t.contains('PERFORMANCE SUMMARY'), 'performance heading');
    System.assert(
      t.contains('Opportunities (campaign rollup): 10 (Won: 4)'),
      'rollup opps'
    );
    System.assert(
      t.contains('Amount, Won Opportunities (rollup): USD 200,000'),
      'won amount'
    );
    System.assert(
      t.contains(
        'Open Pipeline (computed, open opportunities): USD 300,000 across 6'
      ),
      'open pipeline'
    );
    // Gift transaction summary: totals, status breakdown, average — no record list.
    System.assert(t.contains('GIFT TRANSACTION SUMMARY'), 'gift heading');
    System.assert(
      t.contains('Total Received (Paid gift transactions): USD 25,000'),
      'received'
    );
    System.assert(t.contains('Gift Transactions (count): 2'), 'total count');
    System.assert(t.contains('Paid: 1 (USD 25,000)'), 'paid breakdown: ' + t);
    System.assert(t.contains('Pending: 1 (USD 10,000)'), 'pending breakdown');
    System.assert(
      t.contains('Average Gift (Paid): USD 25,000'),
      'average gift'
    );
    // Member summary: totals, response rate, breakdown — no member list.
    System.assert(t.contains('CAMPAIGN MEMBER SUMMARY'), 'member heading');
    System.assert(t.contains('Total Members: 50'), 'member total');
    System.assert(t.contains('40% response rate'), 'response rate: ' + t);
    System.assert(t.contains('BUDGET AND ROI'), 'budget heading');
    System.assert(t.contains('300%'), 'ROI');
    // No individual records leaked into the executive summary.
    System.assert(!t.contains('- Recent:'), 'no per-transaction list');
    System.assert(!t.contains('- Sample:'), 'no per-member list');
  }

  @isTest
  static void notFoundReturnsFoundFalse() {
    CampaignSummaryService svc = new CampaignSummaryService();
    svc.selector = new MockSelector(new CampaignSummaryData());

    CampaignSummaryResult r = svc.getSummary('nope', null);
    System.assertEquals(false, r.found);
  }

  @isTest
  static void handlesEmptyCampaign() {
    CampaignSummaryData d = new CampaignSummaryData();
    d.camp = (Campaign) JSON.deserialize(
      '{"Id":"701000000000009AAA","Name":"New Campaign","IsActive":false,"CurrencyIsoCode":"USD"}',
      Campaign.class
    );
    CampaignSummaryService svc = new CampaignSummaryService();
    svc.selector = new MockSelector(d);

    CampaignSummaryResult r = svc.getSummary(null, '701000000000009AAA');
    System.assertEquals(true, r.found);
    String t = r.resultsText;
    System.assert(
      t.contains('ROI [(Won Amount - Actual Cost) / Actual Cost]: N/A'),
      'ROI N/A'
    );
    System.assert(
      t.contains('Total Received (Paid gift transactions): USD 0'),
      'zero received'
    );
    System.assert(t.contains('By Status: None'), 'no gift statuses');
    System.assert(t.contains('Total Members: 0'), 'no members');
  }

  @isTest
  static void recordRefPopulatedAndTextClean() {
    CampaignSummaryService svc = new CampaignSummaryService();
    svc.selector = new MockSelector(sampleData());
    CampaignSummaryResult r = svc.getSummary('x', null);
    System.assertNotEquals(null, r.record, 'record ref present');
    System.assertEquals('Campaign', r.record.objectApiName, 'object api name');
    System.assert(String.isNotBlank(r.record.recordId), 'record id populated');
    System.assert(
      String.isNotBlank(r.record.recordName),
      'record name populated'
    );
    String t = r.resultsText;
    System.assert(!t.containsIgnoreCase('http'), 'no url in resultsText');
    System.assert(!t.contains('URL_Redacted'), 'no redacted token');
    System.assert(
      !t.contains('701000000000001AAA'),
      'no raw record id in resultsText'
    );
  }
}