/**
 * Builds a deterministic, executive-friendly Account 360 that adapts to the
 * Account Category (Person / Organization / Household / Other), resolved in Apex
 * via AccountClassification (IsPersonAccount + RecordType.DeveloperName + Type —
 * never the name). All figures are computed IN APEX. Related records are capped
 * with totals; financial records are summarized. Uses plain UPPERCASE headings
 * and "•" bullets; the LLM adds Key Insights / Suggested Next Actions per the
 * topic instructions. Only sections/fields with data are rendered.
 */
public with sharing class AccountSummaryService implements IAccountSummaryService {
  @TestVisible
  private IAccountSummarySelector selector = new AccountSummarySelector();

  private static final Set<String> PAID_STATUSES = new Set<String>{ 'Paid' };
  private static final Integer MAX_SHOWN = 5;
  private static final Integer MAX_CAMPAIGNS_SHOWN = 3;

  public AccountSummaryResult getSummary(String searchTerm, Id accountId) {
    AccountSummaryResult result = new AccountSummaryResult();
    AccountSummaryData data = selector.fetch(searchTerm, accountId);

    if (data.acct == null) {
      result.found = false;
      result.resultsText = '';
      return result;
    }

    Account a = data.acct;
    String category = AccountClassification.category(a);
    result.found = true;
    result.accountName = a.Name;
    result.recordId = String.valueOf(a.Id);
    result.objectApiName = 'Account';
    result.accountCategory = category;
    result.recordTypeName = AccountClassification.recordTypeName(a);
    result.recordTypeDeveloperName = AccountClassification.recordTypeDeveloperName(
      a
    );
    result.isPersonAccount = a.IsPersonAccount == true;
    result.accountType = a.Type;
    result.donorType = a.Donor_Type__c;
    result.donorStatus = a.Donor_Status__c;
    result.accountGuardian = a.Account_Guardian__r == null
      ? null
      : a.Account_Guardian__r.Name;
    result.ownerName = a.Owner == null ? null : a.Owner.Name;
    result.record = new AgentRecordResult(a.Id, 'Account', a.Name)
      .withSubtitle(category)
      .withSummary(a.Donor_Segment__c);
    result.records = relatedPeopleRecords(a, data);
    result.resultsText = build(a, data, category);
    return result;
  }

  /**
   * Clickable cards for the related people: a Person Account's affiliated
   * organizations, or an Organization/Household's contacts and affiliations.
   * Navigable by Id (no URL). Deduplicated, capped.
   */
  private List<AgentRecordResult> relatedPeopleRecords(
    Account a,
    AccountSummaryData data
  ) {
    List<AgentRecordResult> refs = new List<AgentRecordResult>();
    Set<Id> seen = new Set<Id>();
    if (AccountClassification.isPerson(a)) {
      for (AccountContactRelation r : data.relationships) {
        if (r.AccountId == null || seen.contains(r.AccountId)) {
          continue;
        }
        seen.add(r.AccountId);
        String nm = r.Account == null ? 'Account' : r.Account.Name;
        refs.add(
          new AgentRecordResult(r.AccountId, 'Account', nm)
            .withSubtitle(rolesText(r.Roles))
        );
        if (refs.size() >= 10) {
          break;
        }
      }
      return refs;
    }
    for (AccountContactRelation r : data.relationships) {
      if (r.ContactId == null || seen.contains(r.ContactId)) {
        continue;
      }
      seen.add(r.ContactId);
      String nm = r.Contact == null ? 'Contact' : r.Contact.Name;
      refs.add(
        new AgentRecordResult(r.ContactId, 'Contact', nm)
          .withSubtitle(rolesText(r.Roles))
      );
      if (refs.size() >= 10) {
        break;
      }
    }
    for (Contact c : data.contacts) {
      if (refs.size() >= 10) {
        break;
      }
      if (seen.contains(c.Id)) {
        continue;
      }
      seen.add(c.Id);
      refs.add(
        new AgentRecordResult(c.Id, 'Contact', c.Name).withSubtitle(c.Title)
      );
    }
    return refs;
  }

  private String rolesText(String roles) {
    return String.isBlank(roles) ? null : roles.replace(';', ', ');
  }

  private String build(Account a, AccountSummaryData data, String category) {
    String cur = String.isBlank(a.CurrencyIsoCode)
      ? ''
      : a.CurrencyIsoCode + ' ';
    Boolean isPerson = AccountClassification.isPerson(a);
    Boolean isHousehold = AccountClassification.isHousehold(a);

    List<String> b = new List<String>();

    // ---- ACCOUNT OVERVIEW (always shows category) ----
    b.add('ACCOUNT OVERVIEW');
    b.add('');
    b.add('• Name: ' + a.Name);
    b.add('• Account Category: ' + category);
    addIf(b, 'Record Type', AccountClassification.recordTypeName(a));
    if (isPerson) {
      addIf(b, 'Donor Type', a.Donor_Type__c);
      addIf(b, 'Donor Status', a.Donor_Status__c);
      addIf(b, 'Account Guardian', guardian(a));
      addIf(b, 'Owner', owner(a));
      addIf(b, 'Email', a.PersonEmail);
      addIf(b, 'Phone', personPhone(a));
      addIf(b, 'Location', personLocation(a));
    } else if (isHousehold) {
      addIf(b, 'Household Type', a.Type);
      addIf(b, 'Donor Status', a.Donor_Status__c);
      addIf(b, 'Owner', owner(a));
      addIf(b, 'Account Guardian', guardian(a));
      addIf(b, 'Location', billingAddress(a));
    } else {
      addIf(b, 'Organization Type', a.Type);
      addIf(b, 'Industry', a.Industry);
      addIf(b, 'Donor Segment', a.Donor_Segment__c);
      addIf(b, 'Donor Type', a.Donor_Type__c);
      addIf(b, 'Donor Status', a.Donor_Status__c);
      addIf(b, 'Account Guardian', guardian(a));
      addIf(b, 'Owner', owner(a));
      addIf(b, 'Parent Account', a.Parent == null ? null : a.Parent.Name);
      addIf(b, 'Website', a.Website);
      addIf(b, 'Phone', a.Phone);
      addIf(b, 'Location', billingAddress(a));
    }

    // ---- RELATED PEOPLE AND RELATIONSHIPS ----
    appendRelatedPeople(b, a, data, isPerson, isHousehold);

    // ---- FUNDRAISING SUMMARY ----
    appendFundraising(b, a, data, cur);

    // ---- DONOR RESEARCH (DonorSearch) ----
    appendDonorResearch(b, data, cur);

    // ---- OPPORTUNITIES ----
    appendOpportunities(b, data, cur);

    // ---- GIFT COMMITMENTS ----
    appendCommitments(b, data, cur);

    // ---- GIFT TRANSACTION SUMMARY ----
    appendTransactions(b, data, cur);

    // ---- CAMPAIGNS ----
    appendCampaigns(b, data, cur);

    // ---- RESTRICTIONS ----
    appendRestrictions(b, data);

    // ---- DATA QUALITY NOTES ----
    b.add('');
    b.add('DATA QUALITY NOTES');
    if (AccountClassification.recordTypeName(a) == null) {
      b.add('• Record Type is missing; category derived from other fields.');
    }
    if (category == AccountClassification.OTHER) {
      b.add(
        '• Account Category could not be confidently determined from Record Type, IsPersonAccount, or Type.'
      );
    }
    b.add(
      '• Amounts are summed without currency conversion; review if the donor gives in multiple currencies.'
    );
    b.add(
      '• Confirmed Received counts only Gift Transactions with status ' +
        String.join(new List<String>(PAID_STATUSES), ', ') +
        '; other statuses appear under By Status.'
    );
    b.add(
      '• Amounts should be reviewed by Grants Finance before being treated as confirmed revenue.'
    );

    return SummaryText.sanitize(String.join(b, '\n'));
  }

  // ---------- section builders ----------

  private void appendRelatedPeople(
    List<String> b,
    Account a,
    AccountSummaryData data,
    Boolean isPerson,
    Boolean isHousehold
  ) {
    b.add('');
    b.add('RELATED PEOPLE AND RELATIONSHIPS');
    if (isPerson) {
      // The person's own affiliations to organizations/households.
      if (data.relationships.isEmpty()) {
        b.add('• No organization or household affiliations on file.');
      } else {
        b.add('• Affiliations: ' + data.relationships.size());
        Integer shown = 0;
        for (AccountContactRelation r : data.relationships) {
          if (shown >= MAX_SHOWN) {
            break;
          }
          String org = r.Account == null ? 'Account' : r.Account.Name;
          b.add('  - ' + org + roleSuffix(r.Roles));
          shown++;
        }
        andMore(b, data.relationships.size());
      }
    } else {
      // Organization / Household: members/contacts, roles, hierarchy.
      String peopleLabel = isHousehold ? 'Household Members' : 'Key Contacts';
      b.add('• ' + peopleLabel + ': ' + data.contacts.size());
      Integer shown = 0;
      for (Contact c : data.contacts) {
        if (shown >= MAX_SHOWN) {
          break;
        }
        b.add(
          '  - ' + c.Name + (String.isBlank(c.Title) ? '' : ' — ' + c.Title)
        );
        shown++;
      }
      andMore(b, data.contacts.size());
      if (!data.relationships.isEmpty()) {
        b.add('• Contact Roles / Affiliations: ' + data.relationships.size());
        Integer rShown = 0;
        for (AccountContactRelation r : data.relationships) {
          if (rShown >= MAX_SHOWN) {
            break;
          }
          String nm = r.Contact == null ? 'Contact' : r.Contact.Name;
          b.add('  - ' + nm + roleSuffix(r.Roles));
          rShown++;
        }
      }
      addIf(b, 'Parent Account', a.Parent == null ? null : a.Parent.Name);
      if (!data.childAccounts.isEmpty()) {
        b.add('• Child Accounts: ' + data.childAccounts.size());
        Integer cShown = 0;
        for (Account child : data.childAccounts) {
          if (cShown >= MAX_SHOWN) {
            break;
          }
          b.add('  - ' + child.Name);
          cShown++;
        }
        andMore(b, data.childAccounts.size());
      }
    }
  }

  private void appendFundraising(
    List<String> b,
    Account a,
    AccountSummaryData data,
    String cur
  ) {
    Decimal committed = null;
    for (GiftCommitment gc : data.commitments) {
      if (gc.ExpectedTotalCmtAmount != null) {
        committed =
          (committed == null ? 0 : committed) + gc.ExpectedTotalCmtAmount;
      }
    }
    Decimal received = paidReceived(data);
    Decimal outstanding = (committed == null ? 0 : committed) - received;

    b.add('');
    b.add('FUNDRAISING SUMMARY');
    b.add('');
    addIf(
      b,
      'Lifetime Giving',
      SummaryText.moneyOrNull(cur, a.Total_Gift_Amount_Donor_Gift_Summary__c)
    );
    b.add('• Total Received (Paid): ' + SummaryText.moneyOrNull(cur, received));
    if (committed != null) {
      b.add(
        '• Total Committed (Expected): ' +
        SummaryText.moneyOrNull(cur, committed)
      );
      b.add(
        '• Outstanding Commitment: ' + SummaryText.moneyOrNull(cur, outstanding)
      );
    }
    b.add('• Gift Commitments: ' + data.commitments.size());
    b.add('• Gift Transactions: ' + data.transactions.size());
    addIf(
      b,
      'Last Gift Amount',
      SummaryText.moneyOrNull(cur, a.Last_Gift_Amount_Donor_Gift_Summary__c)
    );
    if (a.Last_Gift_Date_Donor_Gift_Summary__c != null) {
      b.add(
        '• Last Gift Date: ' +
        FormatUtils.formatDate(a.Last_Gift_Date_Donor_Gift_Summary__c)
      );
    }
    addIf(
      b,
      'Giving This Year',
      SummaryText.moneyOrNull(cur, a.Gifts_this_Year_Donor_Gift_Summary__c)
    );
  }

  /**
   * Third-party wealth & philanthropy intelligence from DonorSearch. Rendered
   * only when a DonorSearch record is present. These are external research
   * estimates (capacity, likelihoods, confirmed philanthropy) — never OAF's own
   * giving figures — so the heading makes the source explicit.
   */
  private void appendDonorResearch(
    List<String> b,
    AccountSummaryData data,
    String cur
  ) {
    DS360oi__DonorSearch_del_del__c ds = data.donorSearch;
    if (ds == null) {
      return;
    }
    // Collect rows first; only emit the section header if any meaningful value
    // survived the zero/empty suppression below.
    List<String> rows = new List<String>();
    addIf(rows, 'DS Rating', ds.DS360oi__DS_Rating__c);
    addIf(
      rows,
      'Estimated Giving Capacity',
      nonZeroRangeText(ds.DS360oi__Capacity_Range_Based_on_Wealth__c)
    );
    Decimal askLow = ds.DS360oi__Largest_Gift_Found_Lower_Range__c;
    Decimal askHigh = ds.DS360oi__Largest_Gift_Found__c;
    if ((askLow != null && askLow > 0) || (askHigh != null && askHigh > 0)) {
      rows.add(
        '• Suggested Ask Range: ' +
          SummaryText.money(cur, askLow) +
          ' – ' +
          SummaryText.money(cur, askHigh)
      );
    }
    addIf(
      rows,
      'Major Gift Likelihood',
      scoreOrNull(ds.DS360oi__Major_Gift_Likelihood__c)
    );
    addIf(
      rows,
      'Planned Gift Likelihood',
      scoreOrNull(ds.DS360oi__Planned_Gift_Likelihood__c)
    );
    addIf(
      rows,
      'Annual Fund Likelihood',
      scoreOrNull(ds.DS360oi__Annual_Fund_Likelihood__c)
    );
    addIf(
      rows,
      'Engagement Score',
      scoreOrNull(ds.DS360oi__Engagement_Score__c)
    );
    addIf(rows, 'AI Score', scoreOrNull(ds.DS360oi__DS_AI_Score__c));
    addIf(
      rows,
      'Aristotle Score',
      scoreOrNull(ds.DS360oi__DonorSearch_Aristotle_Score__c)
    );
    addIf(
      rows,
      'Confirmed Philanthropy (Total)',
      moneyIfPositive(cur, ds.DS360oi__Philanthropy_and_Grant_making_Total__c)
    );
    if (
      ds.DS360oi__Charitable_Gift_count__c != null &&
      ds.DS360oi__Charitable_Gift_count__c > 0
    ) {
      rows.add(
        '• Confirmed Charitable Gifts: ' +
        String.valueOf(ds.DS360oi__Charitable_Gift_count__c.intValue())
      );
    }
    addIf(rows, 'Largest Gift Recipient', ds.DS360oi__Largest_Gift_Org__c);

    if (rows.isEmpty()) {
      return;
    }
    b.add('');
    b.add('DONOR RESEARCH (DonorSearch)');
    b.add('');
    b.addAll(rows);
  }

  /**
   * A DonorSearch numeric score, or null when it is absent or a placeholder
   * zero (DonorSearch stores "no signal" as 0, which is noise in the summary).
   */
  private String scoreOrNull(Decimal d) {
    return (d == null || d == 0) ? null : String.valueOf(d);
  }

  /** Formatted money, or null when the amount is absent or non-positive. */
  private String moneyIfPositive(String cur, Decimal d) {
    return (d == null || d <= 0) ? null : SummaryText.moneyOrNull(cur, d);
  }

  /**
   * A capacity/range text value, or null when it is blank or an all-zero
   * placeholder like "$0 - $0" that carries no information.
   */
  private String nonZeroRangeText(String value) {
    if (String.isBlank(value)) {
      return null;
    }
    String digits = value.replaceAll('[^0-9]', '');
    if (String.isBlank(digits)) {
      // Non-numeric label (e.g. "Unknown") — keep it; only suppress zero ranges.
      return value;
    }
    return (digits.replaceAll('0', '') == '') ? null : value;
  }

  private void appendOpportunities(
    List<String> b,
    AccountSummaryData data,
    String cur
  ) {
    b.add('');
    b.add('OPPORTUNITIES (' + data.opportunities.size() + ')');
    if (data.opportunities.isEmpty()) {
      b.add('• None linked.');
      return;
    }
    Integer awarded = 0, closed = 0, open = 0;
    for (Opportunity o : data.opportunities) {
      String st = o.StageName == null ? '' : o.StageName.toLowerCase();
      if (st.contains('awarded')) {
        awarded++;
      } else if (st.contains('closed') || st.contains('denied')) {
        closed++;
      } else {
        open++;
      }
    }
    b.add(
      '• Open: ' + open + '   Awarded: ' + awarded + '   Closed: ' + closed
    );
    Integer shown = 0;
    for (Opportunity o : data.opportunities) {
      if (shown >= MAX_SHOWN) {
        break;
      }
      b.add('');
      b.add(o.Name);
      addIf(b, 'Stage', o.StageName);
      if (o.Amount != null) {
        b.add('• Amount: ' + SummaryText.moneyOrNull(cur, o.Amount));
      }
      if (o.CloseDate != null) {
        b.add('• Close Date: ' + FormatUtils.formatDate(o.CloseDate));
      }
      shown++;
    }
    andMore(b, data.opportunities.size());
  }

  private void appendCommitments(
    List<String> b,
    AccountSummaryData data,
    String cur
  ) {
    b.add('');
    b.add('GIFT COMMITMENTS (' + data.commitments.size() + ')');
    if (data.commitments.isEmpty()) {
      b.add('• None linked.');
      return;
    }
    Integer shown = 0;
    for (GiftCommitment gc : data.commitments) {
      if (shown >= MAX_SHOWN) {
        break;
      }
      b.add('');
      b.add(gc.Name);
      addIf(b, 'Status', gc.Status);
      if (gc.ExpectedTotalCmtAmount != null) {
        b.add(
          '• Expected Amount: ' +
          SummaryText.moneyOrNull(cur, gc.ExpectedTotalCmtAmount)
        );
      }
      if (gc.EffectiveStartDate != null) {
        b.add('• Start Date: ' + FormatUtils.formatDate(gc.EffectiveStartDate));
      }
      if (gc.ExpectedEndDate != null) {
        b.add('• End Date: ' + FormatUtils.formatDate(gc.ExpectedEndDate));
      }
      shown++;
    }
    andMore(b, data.commitments.size());
  }

  private void appendTransactions(
    List<String> b,
    AccountSummaryData data,
    String cur
  ) {
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
    Integer txnTotal = data.transactions.size();
    Decimal avgPaid = paidCount > 0 ? received / paidCount : null;

    b.add('');
    b.add('GIFT TRANSACTION SUMMARY');
    b.add('');
    b.add('• Total Transactions: ' + txnTotal);
    b.add('• Paid: ' + paidCount + '   Unpaid: ' + (txnTotal - paidCount));
    b.add('• Total Paid Value: ' + SummaryText.moneyOrNull(cur, received));
    addIf(b, 'Average Paid Gift', SummaryText.moneyOrNull(cur, avgPaid));
    b.add(
      '• By Status: ' +
      SummaryText.statusBreakdown(cur, countByStatus, amountByStatus)
    );
  }

  private void appendCampaigns(
    List<String> b,
    AccountSummaryData data,
    String cur
  ) {
    List<CampaignAgg> campaigns = aggregateCampaigns(data.opportunities);
    if (campaigns.isEmpty()) {
      return;
    }
    b.add('');
    b.add('CAMPAIGNS');
    campaigns.sort();
    Integer shown = 0;
    for (CampaignAgg ca : campaigns) {
      if (shown >= MAX_CAMPAIGNS_SHOWN) {
        break;
      }
      b.add('');
      b.add(ca.name);
      addIf(b, 'Status', ca.status);
      b.add('• Related Opportunities: ' + ca.oppCount);
      b.add('• Funds Raised: ' + SummaryText.moneyOrNull(cur, ca.funds));
      shown++;
    }
  }

  private void appendRestrictions(List<String> b, AccountSummaryData data) {
    if (data.restrictions.isEmpty()) {
      return;
    }
    b.add('');
    b.add('RESTRICTIONS (' + data.restrictions.size() + ')');
    Integer shown = 0;
    for (Restriction__c r : data.restrictions) {
      if (shown >= MAX_SHOWN) {
        break;
      }
      String country = String.isBlank(r.Restriction_Country__c)
        ? ''
        : ' (Country: ' + r.Restriction_Country__c + ')';
      b.add('• ' + r.Name + country);
      shown++;
    }
    andMore(b, data.restrictions.size());
  }

  // ---------- helpers ----------

  private Decimal paidReceived(AccountSummaryData data) {
    Decimal received = 0;
    for (GiftTransaction gt : data.transactions) {
      if (PAID_STATUSES.contains(gt.Status) && gt.CurrentAmount != null) {
        received += gt.CurrentAmount;
      }
    }
    return received;
  }

  private void andMore(List<String> b, Integer total) {
    Integer extra = total - MAX_SHOWN;
    if (extra > 0) {
      b.add('...and ' + extra + ' additional records.');
    }
  }

  private String roleSuffix(String roles) {
    return String.isBlank(roles) ? '' : ' — ' + roles.replace(';', ', ');
  }

  private String guardian(Account a) {
    return a.Account_Guardian__r == null ? null : a.Account_Guardian__r.Name;
  }

  private String owner(Account a) {
    return a.Owner == null ? null : a.Owner.Name;
  }

  private String personPhone(Account a) {
    if (String.isNotBlank(a.PersonMobilePhone)) {
      return a.PersonMobilePhone;
    }
    return a.PersonHomePhone;
  }

  private String personLocation(Account a) {
    List<String> parts = new List<String>();
    if (String.isNotBlank(a.PersonMailingCity)) {
      parts.add(a.PersonMailingCity);
    }
    if (String.isNotBlank(a.PersonMailingState)) {
      parts.add(a.PersonMailingState);
    }
    if (String.isNotBlank(a.PersonMailingCountry)) {
      parts.add(a.PersonMailingCountry);
    }
    return parts.isEmpty() ? null : String.join(parts, ', ');
  }

  private void addIf(List<String> b, String label, String value) {
    if (String.isNotBlank(value)) {
      b.add('• ' + label + ': ' + value);
    }
  }

  private String billingAddress(Account a) {
    List<String> parts = new List<String>();
    if (String.isNotBlank(a.BillingCity)) {
      parts.add(a.BillingCity);
    }
    if (String.isNotBlank(a.BillingState)) {
      parts.add(a.BillingState);
    }
    if (String.isNotBlank(a.BillingCountry)) {
      parts.add(a.BillingCountry);
    }
    return parts.isEmpty() ? null : String.join(parts, ', ');
  }

  private List<CampaignAgg> aggregateCampaigns(List<Opportunity> opps) {
    Map<Id, CampaignAgg> byCampaign = new Map<Id, CampaignAgg>();
    for (Opportunity o : opps) {
      if (o.CampaignId == null) {
        continue;
      }
      CampaignAgg ca = byCampaign.get(o.CampaignId);
      if (ca == null) {
        ca = new CampaignAgg();
        ca.name = o.Campaign == null ? 'Campaign' : o.Campaign.Name;
        ca.status = o.Campaign == null ? null : o.Campaign.Status;
        byCampaign.put(o.CampaignId, ca);
      }
      ca.oppCount++;
      if (o.Amount != null) {
        ca.funds += o.Amount;
      }
    }
    return byCampaign.values();
  }

  /** Account-scoped campaign rollup (this account's opportunities only). */
  private class CampaignAgg implements Comparable {
    private String name;
    private String status;
    private Integer oppCount = 0;
    private Decimal funds = 0;
    public Integer compareTo(Object other) {
      CampaignAgg o = (CampaignAgg) other;
      if (funds == o.funds) {
        return 0;
      }
      return funds < o.funds ? 1 : -1;
    }
  }
}