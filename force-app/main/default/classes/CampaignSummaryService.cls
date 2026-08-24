/**
 * Builds a deterministic, executive-friendly Campaign Performance 360: campaign
 * rollups, live open pipeline, and gift-transaction / campaign-member summaries
 * (totals, status breakdowns, averages, response rate). All figures computed IN
 * APEX (never the LLM). No per-record lists — record-level detail is a separate
 * request. Plain-text headings (the agent UI shows markdown symbols literally).
 */
public with sharing class CampaignSummaryService implements ICampaignSummaryService {
  @TestVisible
  private ICampaignSummarySelector selector = new CampaignSummarySelector();

  public CampaignSummaryResult getSummary(String searchTerm, Id campaignId) {
    CampaignSummaryResult result = new CampaignSummaryResult();
    CampaignSummaryData data = selector.fetch(searchTerm, campaignId);

    if (data.camp == null) {
      result.found = false;
      result.resultsText = '';
      return result;
    }

    Campaign c = data.camp;
    result.found = true;
    result.campaignName = c.Name;
    result.recordId = String.valueOf(c.Id);
    result.objectApiName = 'Campaign';
    result.record = new AgentRecordResult(c.Id, 'Campaign', c.Name)
      .withSubtitle(c.Status)
      .withSummary(c.Type);
    result.resultsText = build(c, data);
    return result;
  }

  private String build(Campaign c, CampaignSummaryData data) {
    String cur = String.isBlank(c.CurrencyIsoCode)
      ? ''
      : c.CurrencyIsoCode + ' ';

    Decimal roi = null;
    if (
      c.ActualCost != null &&
      c.ActualCost != 0 &&
      c.AmountWonOpportunities != null
    ) {
      roi = ((c.AmountWonOpportunities - c.ActualCost) / c.ActualCost) * 100;
    }
    Decimal received = data.giftReceivedAmount == null
      ? 0
      : data.giftReceivedAmount;
    Decimal avgGift = (data.paidGiftTransactionCount != null &&
      data.paidGiftTransactionCount > 0)
      ? (received / data.paidGiftTransactionCount)
      : null;
    Decimal responseRate = (data.memberCount != null &&
      data.memberCount > 0 &&
      data.respondedMemberCount != null)
      ? ((Decimal) data.respondedMemberCount / data.memberCount) * 100
      : null;

    List<String> b = new List<String>();
    b.add('Campaign Summary: ' + c.Name);
    b.add('');
    b.add('CAMPAIGN OVERVIEW');
    b.add('• Campaign: ' + c.Name);
    b.add('• Type: ' + (String.isBlank(c.Type) ? 'N/A' : c.Type));
    b.add('• Status: ' + (String.isBlank(c.Status) ? 'N/A' : c.Status));
    b.add('• Active: ' + (c.IsActive == true ? 'Yes' : 'No'));
    b.add(
      '• Start: ' +
        (c.StartDate == null ? 'N/A' : FormatUtils.formatDate(c.StartDate)) +
        '   End: ' +
        (c.EndDate == null ? 'N/A' : FormatUtils.formatDate(c.EndDate))
    );
    b.add('• Owner: ' + (c.Owner == null ? 'N/A' : c.Owner.Name));
    b.add('');
    b.add('PERFORMANCE SUMMARY');
    b.add(
      '• Opportunities (campaign rollup): ' +
        nvlInt(c.NumberOfOpportunities) +
        ' (Won: ' +
        nvlInt(c.NumberOfWonOpportunities) +
        ')'
    );
    b.add(
      '• Amount, All Opportunities (rollup): ' +
      SummaryText.money(cur, c.AmountAllOpportunities)
    );
    b.add(
      '• Amount, Won Opportunities (rollup): ' +
      SummaryText.money(cur, c.AmountWonOpportunities)
    );
    b.add(
      '• Open Pipeline (computed, open opportunities): ' +
        SummaryText.money(cur, data.openPipelineAmount) +
        ' across ' +
        nvlInt(data.openOpportunityCount)
    );
    b.add('');
    b.add('GIFT TRANSACTION SUMMARY');
    b.add(
      '• Total Received (Paid gift transactions): ' +
      SummaryText.money(cur, received)
    );
    b.add(
      '• Gift Transactions (count): ' + nvlInt(data.totalGiftTransactionCount)
    );
    b.add(
      '• By Status: ' +
      SummaryText.statusBreakdown(
        cur,
        data.giftCountByStatus,
        data.giftAmountByStatus
      )
    );
    b.add('• Average Gift (Paid): ' + SummaryText.money(cur, avgGift));
    b.add('');
    b.add('CAMPAIGN MEMBER SUMMARY');
    b.add('• Total Members: ' + nvlInt(data.memberCount));
    b.add(
      '• Responded: ' +
        nvlInt(data.respondedMemberCount) +
        (responseRate == null
          ? ''
          : ' (' + responseRate.setScale(0) + '% response rate)')
    );
    b.add(
      '• By Status: ' + SummaryText.countBreakdown(data.memberStatusCounts)
    );
    b.add('');
    b.add('BUDGET AND ROI');
    b.add('• Budgeted Cost: ' + SummaryText.money(cur, c.BudgetedCost));
    b.add('• Actual Cost: ' + SummaryText.money(cur, c.ActualCost));
    b.add('• Expected Revenue: ' + SummaryText.money(cur, c.ExpectedRevenue));
    b.add(
      '• ROI [(Won Amount - Actual Cost) / Actual Cost]: ' +
      (roi == null ? 'N/A' : roi.setScale(0) + '%')
    );
    b.add('');
    b.add('DATA QUALITY NOTES');
    b.add(
      '• Opportunity counts and All/Won amounts are Salesforce-maintained campaign rollups; Open Pipeline is computed live from open opportunities.'
    );
    b.add(
      '• Gift Transactions include those attributed directly to the campaign and those made against a gift commitment linked to the campaign.'
    );
    b.add(
      '• "Received" counts only Paid gift transactions. Pending/Failed/Refunded/Cancelled are shown under By Status but excluded from Received.'
    );
    b.add('• Amounts are summed without currency conversion.');
    return SummaryText.sanitize(String.join(b, '\n'));
  }

  private String nvlInt(Integer value) {
    return value == null ? '0' : String.valueOf(value);
  }
}