/**
 * Builds a deterministic Opportunity 360 summary: gathers the Opportunity and its
 * linked Gift Commitment(s), Gift Transactions, and Restrictions, then computes
 * received vs. outstanding funding IN APEX (never in the LLM) and renders a
 * grounded, human-readable summary. Fields that require finance business rules
 * (restriction sync / unallocated) are explicitly marked as not yet evaluated.
 */
public with sharing class OpportunitySummaryService implements IOpportunitySummaryService {
  @TestVisible
  private IOpportunitySummarySelector selector = new OpportunitySummarySelector();

  /** Gift Transaction statuses treated as confirmed/received in v1. */
  private static final Set<String> PAID_STATUSES = new Set<String>{ 'Paid' };
  private static final Integer MAX_RESTRICTIONS_SHOWN = 10;

  public OpportunitySummaryResult getSummary(
    String searchTerm,
    Id opportunityId
  ) {
    OpportunitySummaryResult result = new OpportunitySummaryResult();
    OpportunitySummaryData data = selector.fetch(searchTerm, opportunityId);

    if (data.opp == null) {
      result.found = false;
      result.resultsText = '';
      return result;
    }

    Opportunity o = data.opp;
    result.found = true;
    result.opportunityName = o.Name;
    result.recordId = String.valueOf(o.Id);
    result.objectApiName = 'Opportunity';
    result.record = new AgentRecordResult(o.Id, 'Opportunity', o.Name)
      .withSubtitle(o.StageName)
      .withSummary(SummaryText.moneyOrNull(o.CurrencyIsoCode, o.Amount));
    result.resultsText = build(o, data);
    return result;
  }

  private String build(Opportunity o, OpportunitySummaryData data) {
    String cur = String.isBlank(o.CurrencyIsoCode)
      ? ''
      : o.CurrencyIsoCode + ' ';

    Decimal expected = o.Amount;
    Decimal commitmentExpected = null;
    for (GiftCommitment gc : data.commitments) {
      if (gc.ExpectedTotalCmtAmount != null) {
        commitmentExpected =
          (commitmentExpected == null ? 0 : commitmentExpected) +
          gc.ExpectedTotalCmtAmount;
      }
    }

    Map<String, Integer> countByStatus = new Map<String, Integer>();
    Map<String, Decimal> amountByStatus = new Map<String, Decimal>();
    Decimal confirmedReceived = 0;
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
        confirmedReceived += gt.CurrentAmount;
        paidCount++;
      }
    }

    Decimal basis = expected != null
      ? expected
      : (commitmentExpected != null ? commitmentExpected : 0);
    Decimal outstanding = basis - confirmedReceived;
    Decimal avgGift = paidCount > 0 ? confirmedReceived / paidCount : null;

    List<String> b = new List<String>();
    b.add('Opportunity Summary: ' + o.Name);
    b.add('');
    b.add('OVERVIEW');
    b.add('• Opportunity: ' + o.Name);
    b.add('• Account: ' + (o.Account == null ? 'N/A' : o.Account.Name));
    b.add('• Stage: ' + (String.isBlank(o.StageName) ? 'N/A' : o.StageName));
    b.add('• Amount: ' + SummaryText.money(cur, o.Amount));
    b.add(
      '• Probability: ' +
      (o.Probability == null ? 'N/A' : String.valueOf(o.Probability) + '%')
    );
    b.add('• Close Date: ' + FormatUtils.formatDate(o.CloseDate));
    b.add('• Owner: ' + (o.Owner == null ? 'N/A' : o.Owner.Name));
    b.add(
      '• Campaign: ' +
      (o.CampaignId == null
        ? 'Not linked'
        : (o.Campaign == null ? 'N/A' : o.Campaign.Name))
    );
    b.add('');
    b.add('FUNDING CONTEXT');
    b.add('• Expected Opportunity Amount: ' + SummaryText.money(cur, expected));
    if (data.commitments.isEmpty()) {
      b.add('• Gift Commitment: None linked');
    } else {
      List<String> names = new List<String>();
      for (GiftCommitment gc : data.commitments) {
        names.add(gc.Name);
      }
      b.add('• Gift Commitment: ' + String.join(names, '; '));
      b.add(
        '• Commitment Expected Total: ' +
        SummaryText.money(cur, commitmentExpected)
      );
    }
    b.add('• Gift Transactions Found: ' + data.transactions.size());
    b.add(
      '• Confirmed Received (Paid): ' +
      SummaryText.money(cur, confirmedReceived)
    );
    b.add(
      '• By Status: ' +
      SummaryText.statusBreakdown(cur, countByStatus, amountByStatus)
    );
    b.add('• Average Gift (Paid): ' + SummaryText.money(cur, avgGift));
    b.add(
      '• Outstanding / Expected Amount: ' + SummaryText.money(cur, outstanding)
    );
    b.add('');
    b.add('RESTRICTIONS');
    if (data.restrictions.isEmpty()) {
      b.add('• Related Restrictions: None linked');
    } else {
      Integer shown = 0;
      for (Restriction__c r : data.restrictions) {
        if (shown >= MAX_RESTRICTIONS_SHOWN) {
          b.add(
            '• ... and ' +
              (data.restrictions.size() - MAX_RESTRICTIONS_SHOWN) +
              ' more'
          );
          break;
        }
        b.add(
          '• ' +
            r.Name +
            (String.isBlank(r.Restriction_Country__c)
              ? ''
              : ' (Country: ' + r.Restriction_Country__c + ')') +
            ' — Allocated: ' +
            SummaryText.money(cur, RestrictionAllocation.totalAllocated(r))
        );
        shown++;
      }
    }
    RestrictionAllocation.Reconciliation recon = RestrictionAllocation.reconcile(
      commitmentExpected,
      data.restrictions
    );
    b.add(
      '• Total Restriction Allocated: ' +
      SummaryText.money(cur, recon.allocated)
    );
    b.add(
      '• Unallocated (Commitment Expected − Allocated): ' +
      SummaryText.money(cur, recon.unallocated)
    );
    b.add('• Restriction Status: ' + recon.status);
    b.add('');
    b.add('DATA QUALITY NOTES');
    if (data.commitments.isEmpty()) {
      b.add('• No Gift Commitment linked to this Opportunity.');
    }
    if (data.transactions.isEmpty()) {
      b.add(
        '• No Gift Transactions found (matched via the linked Gift Commitment).'
      );
    }
    if (o.CampaignId == null) {
      b.add('• No Campaign linked.');
    }
    b.add(
      '• Confirmed Received counts only Gift Transactions with status ' +
        String.join(new List<String>(PAID_STATUSES), ', ') +
        '.'
    );
    b.add(
      '• Amounts should be reviewed by Grants Finance before being treated as confirmed revenue.'
    );
    return SummaryText.sanitize(String.join(b, '\n'));
  }
}