/**
 * Builds a deterministic Restriction 360: presents the restriction's purpose and
 * its parent gift commitment context, and computes Total Allocated IN APEX as the
 * sum of the yearly Funds Allocated fields (a grounded "restriction amount"), with
 * a per-year breakdown.
 */
public with sharing class RestrictionSummaryService implements IRestrictionSummaryService {
  @TestVisible
  private IRestrictionSummarySelector selector = new RestrictionSummarySelector();

  private static final Integer FIRST_YEAR = RestrictionSummarySelector.FIRST_YEAR;
  private static final Integer LAST_YEAR = RestrictionSummarySelector.LAST_YEAR;

  public RestrictionSummaryResult getSummary(
    String searchTerm,
    Id restrictionId
  ) {
    RestrictionSummaryResult result = new RestrictionSummaryResult();
    Restriction__c r = selector.fetch(searchTerm, restrictionId);

    if (r == null) {
      result.found = false;
      result.resultsText = '';
      return result;
    }

    result.found = true;
    result.restrictionName = r.Name;
    result.recordId = String.valueOf(r.Id);
    result.objectApiName = 'Restriction__c';
    result.record = new AgentRecordResult(r.Id, 'Restriction__c', r.Name)
      .withSubtitle(r.Restriction_Country__c)
      .withSummary(r.Theme__c);
    result.resultsText = build(r);
    return result;
  }

  private String build(Restriction__c r) {
    String cur = String.isBlank(r.CurrencyIsoCode)
      ? ''
      : r.CurrencyIsoCode + ' ';

    Decimal totalAllocated = null;
    List<String> yearLines = new List<String>();
    for (Integer y = FIRST_YEAR; y <= LAST_YEAR; y++) {
      Object value = r.get('x' + y + '_Funds_Allocated__c');
      if (value != null) {
        Decimal amt = (Decimal) value;
        if (amt != 0) {
          totalAllocated = (totalAllocated == null ? 0 : totalAllocated) + amt;
          yearLines.add('  • ' + y + ': ' + SummaryText.money(cur, amt));
        }
      }
    }

    GiftCommitment gc = r.Gift_Commitment__r;
    String commitmentName = r.Gift_Commitment__c == null
      ? 'Not linked'
      : (gc == null ? 'N/A' : gc.Name);
    String donorName = (gc == null || gc.Donor == null) ? 'N/A' : gc.Donor.Name;

    List<String> b = new List<String>();
    b.add('Restriction 360: ' + r.Name);
    b.add('');
    b.add('OVERVIEW');
    b.add('• Restriction: ' + r.Name);
    b.add('• Gift Commitment: ' + commitmentName);
    b.add('• Donor: ' + donorName);
    b.add(
      '• Country: ' +
      (String.isBlank(r.Restriction_Country__c)
        ? 'N/A'
        : r.Restriction_Country__c)
    );
    b.add('• Theme: ' + (String.isBlank(r.Theme__c) ? 'N/A' : r.Theme__c));
    b.add(
      '• Staff / Overhead: ' +
      (String.isBlank(r.Staff_or_Overhead__c) ? 'N/A' : r.Staff_or_Overhead__c)
    );
    b.add(
      '• Time Restricted: ' +
      (String.isBlank(r.Is_this_grant_time_restricted__c)
        ? 'N/A'
        : r.Is_this_grant_time_restricted__c)
    );
    Boolean isSubGrantee = r.Is_this_a_grant_to_a_sub_grantee__c == 'Yes';
    b.add(
      '• Sub-grantee: ' +
      (isSubGrantee
        ? (String.isBlank(r.Sub_grantee_Name__c)
            ? 'Yes'
            : r.Sub_grantee_Name__c)
        : 'No')
    );
    b.add('');
    b.add('ALLOCATION');
    b.add(
      '• Total Allocated (sum of yearly funds): ' +
      SummaryText.money(cur, totalAllocated)
    );
    if (r.Time_Allocation__c != null) {
      b.add('• Time Allocation: ' + r.Time_Allocation__c.setScale(0) + '%');
    }
    if (yearLines.isEmpty()) {
      b.add('• By Year: none recorded');
    } else {
      b.add('• By Year:');
      b.addAll(yearLines);
    }
    b.add('');
    b.add('NOTES');
    b.add(
      '• ' +
      (String.isBlank(r.Additional_Restriction_Notes__c)
        ? 'None'
        : r.Additional_Restriction_Notes__c)
    );
    b.add('');
    b.add('DATA QUALITY NOTES');
    b.add(
      '• Total Allocated is the sum of the yearly Funds Allocated fields (' +
        FIRST_YEAR +
        '–' +
        LAST_YEAR +
        ').'
    );
    b.add('• Amounts are summed without currency conversion.');
    return SummaryText.sanitize(String.join(b, '\n'));
  }
}