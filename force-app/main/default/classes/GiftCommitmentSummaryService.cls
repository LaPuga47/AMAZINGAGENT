/**
 * Builds a deterministic, executive-friendly Gift Commitment 360: gathers the
 * commitment, its gift transactions, and restrictions, then computes received vs.
 * outstanding, a gift status breakdown, and restriction reconciliation IN APEX
 * (never the LLM). Totals/breakdowns only — no per-record lists. Plain-text
 * headings (the agent UI shows markdown symbols literally).
 */
public with sharing class GiftCommitmentSummaryService implements IGiftCommitmentSummaryService {
  @TestVisible
  private IGiftCommitmentSummarySelector selector = new GiftCommitmentSummarySelector();

  private static final Set<String> PAID_STATUSES = new Set<String>{ 'Paid' };

  public GiftCommitmentSummaryResult getSummary(
    String searchTerm,
    Id commitmentId
  ) {
    GiftCommitmentSummaryResult result = new GiftCommitmentSummaryResult();
    GiftCommitmentSummaryData data = selector.fetch(searchTerm, commitmentId);

    if (data.commitment == null) {
      result.found = false;
      result.resultsText = '';
      return result;
    }

    GiftCommitment gc = data.commitment;
    result.found = true;
    result.commitmentName = gc.Name;
    result.recordId = String.valueOf(gc.Id);
    result.objectApiName = 'GiftCommitment';
    result.record = new AgentRecordResult(gc.Id, 'GiftCommitment', gc.Name)
      .withSubtitle(gc.Status)
      .withSummary(
        SummaryText.moneyOrNull(gc.CurrencyIsoCode, gc.ExpectedTotalCmtAmount)
      );
    result.resultsText = build(gc, data);
    return result;
  }

  private String build(GiftCommitment gc, GiftCommitmentSummaryData data) {
    String cur = String.isBlank(gc.CurrencyIsoCode)
      ? ''
      : gc.CurrencyIsoCode + ' ';

    Map<String, Integer> countByStatus = new Map<String, Integer>();
    Map<String, Decimal> amountByStatus = new Map<String, Decimal>();
    Decimal received = 0;
    Integer paidCount = 0;
    for (GiftTransaction gt : data.transactions) {
      String st = String.isBlank(gt.Status) ? 'None' : gt.Status;
      Decimal amt = gt.CurrentAmount == null ? 0 : gt.CurrentAmount;
      countByStatus.put(
        st,
        (countByStatus.containsKey(st) ? countByStatus.get(st) : 0) + 1
      );
      amountByStatus.put(
        st,
        (amountByStatus.containsKey(st) ? amountByStatus.get(st) : 0) + amt
      );
      if (PAID_STATUSES.contains(gt.Status) && gt.CurrentAmount != null) {
        received += gt.CurrentAmount;
        paidCount++;
      }
    }
    Decimal expected = gc.ExpectedTotalCmtAmount;
    Decimal outstanding = (expected == null ? 0 : expected) - received;
    Decimal avgGift = paidCount > 0 ? received / paidCount : null;

    List<String> b = new List<String>();
    b.add('Gift Commitment 360: ' + gc.Name);
    b.add('');
    b.add('OVERVIEW');
    b.add('• Gift Commitment: ' + gc.Name);
    b.add('• Donor: ' + (gc.Donor == null ? 'N/A' : gc.Donor.Name));
    b.add('• Status: ' + (String.isBlank(gc.Status) ? 'N/A' : gc.Status));
    b.add(
      '• Opportunity: ' +
      (gc.OpportunityId == null
        ? 'Not linked'
        : (gc.Opportunity == null ? 'N/A' : gc.Opportunity.Name))
    );
    b.add(
      '• Campaign: ' +
      (gc.CampaignId == null
        ? 'Not linked'
        : (gc.Campaign == null ? 'N/A' : gc.Campaign.Name))
    );
    b.add(
      '• Start: ' +
        (gc.EffectiveStartDate == null
          ? 'N/A'
          : FormatUtils.formatDate(gc.EffectiveStartDate)) +
        '   Expected End: ' +
        (gc.ExpectedEndDate == null
          ? 'N/A'
          : FormatUtils.formatDate(gc.ExpectedEndDate))
    );
    b.add('');
    b.add('FUNDING');
    b.add('• Expected Total: ' + SummaryText.money(cur, expected));
    b.add(
      '• Total Paid (rollup): ' +
      SummaryText.money(cur, gc.TotalPaidTransactionAmount)
    );
    b.add(
      '• Confirmed Received (Paid transactions, computed): ' +
      SummaryText.money(cur, received)
    );
    b.add(
      '• Remaining Balance (rollup): ' +
      SummaryText.money(cur, gc.Remaining_Balance__c)
    );
    b.add(
      '• Outstanding (Expected - Received, computed): ' +
      SummaryText.money(cur, outstanding)
    );
    b.add('');
    b.add('SCHEDULE');
    b.add(
      '• Recurrence: ' +
      (String.isBlank(gc.RecurrenceType) ? 'N/A' : gc.RecurrenceType)
    );
    b.add(
      '• Schedule Type: ' +
      (String.isBlank(gc.ScheduleType) ? 'N/A' : gc.ScheduleType)
    );
    String next = gc.NextTransactionDate == null
      ? 'N/A'
      : FormatUtils.formatDate(gc.NextTransactionDate);
    if (gc.NextTransactionAmount != null) {
      next += ' (' + SummaryText.money(cur, gc.NextTransactionAmount) + ')';
    }
    b.add('• Next Payment: ' + next);
    b.add('');
    b.add('GIFT TRANSACTION SUMMARY');
    b.add(
      '• Gift Transactions (count): ' +
        data.transactions.size() +
        ' (Paid: ' +
        paidCount +
        ')'
    );
    b.add(
      '• By Status: ' +
      SummaryText.statusBreakdown(cur, countByStatus, amountByStatus)
    );
    b.add('• Average Gift (Paid): ' + SummaryText.money(cur, avgGift));
    b.add('');
    b.add('RESTRICTION SUMMARY (' + data.restrictions.size() + ')');
    RestrictionAllocation.Reconciliation recon = RestrictionAllocation.reconcile(
      expected,
      data.restrictions
    );
    b.add(
      '• Total Restriction Allocated: ' +
      SummaryText.money(cur, recon.allocated)
    );
    b.add(
      '• Unallocated (Expected - Allocated): ' +
      SummaryText.money(cur, recon.unallocated)
    );
    b.add('• Restriction Status: ' + recon.status);
    b.add('');
    b.add('DATA QUALITY NOTES');
    b.add(
      '• Total Paid and Remaining Balance are Salesforce-maintained rollup fields; Confirmed Received is computed live from Paid transactions and may differ if rollups are stale.'
    );
    b.add(
      '• "Received" counts only Paid gift transactions; other statuses are shown under By Status.'
    );
    b.add('• Amounts are summed without currency conversion.');
    b.add(
      '• Amounts should be reviewed by Grants Finance before being treated as confirmed revenue.'
    );
    return SummaryText.sanitize(String.join(b, '\n'));
  }
}