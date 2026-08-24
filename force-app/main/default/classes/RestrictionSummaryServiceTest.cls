@isTest
private class RestrictionSummaryServiceTest {
  private class MockSelector implements IRestrictionSummarySelector {
    private Restriction__c toReturn;
    private MockSelector(Restriction__c r) {
      this.toReturn = r;
    }
    public Restriction__c fetch(String searchTerm, Id restrictionId) {
      return toReturn;
    }
  }

  private static Restriction__c sample() {
    return (Restriction__c) JSON.deserialize(
      '{"Id":"a0L000000000001AAA","Name":"R2025-100","Gift_Commitment__c":"6gc000000000001AAA",' +
        '"Restriction_Country__c":"Kenya","Theme__c":"Agriculture","Staff_or_Overhead__c":"Staff",' +
        '"Is_this_grant_time_restricted__c":"Yes","Time_Allocation__c":75,' +
        '"Additional_Restriction_Notes__c":"Seed programs only","Is_this_a_grant_to_a_sub_grantee__c":"No",' +
        '"x2025_Funds_Allocated__c":100000,"x2026_Funds_Allocated__c":150000,"CurrencyIsoCode":"USD",' +
        '"Gift_Commitment__r":{"Name":"Big Multi-Year Pledge"}}',
      Restriction__c.class
    );
  }

  @isTest
  static void buildsGroundedRestrictionSummaryWithAllocationTotal() {
    RestrictionSummaryService svc = new RestrictionSummaryService();
    svc.selector = new MockSelector(sample());

    RestrictionSummaryResult r = svc.getSummary('R2025', null);

    System.assertEquals(true, r.found);
    System.assertEquals('R2025-100', r.restrictionName);
    String t = r.resultsText;
    System.assert(t.contains('Restriction 360: R2025-100'), 'header');
    System.assert(
      t.contains('Gift Commitment: Big Multi-Year Pledge'),
      'commitment'
    );
    System.assert(t.contains('Country: Kenya'), 'country');
    // Total Allocated = 100,000 + 150,000 = 250,000
    System.assert(
      t.contains('Total Allocated (sum of yearly funds): USD 250,000'),
      'total allocated: ' + t
    );
    System.assert(t.contains('2025: USD 100,000'), 'year 2025');
    System.assert(t.contains('2026: USD 150,000'), 'year 2026');
    System.assert(t.contains('Time Allocation: 75%'), 'time allocation');
  }

  @isTest
  static void notFoundReturnsFoundFalse() {
    RestrictionSummaryService svc = new RestrictionSummaryService();
    svc.selector = new MockSelector(null);

    RestrictionSummaryResult r = svc.getSummary('nope', null);
    System.assertEquals(false, r.found);
  }

  @isTest
  static void handlesNoAllocationsAndNoCommitment() {
    Restriction__c bare = (Restriction__c) JSON.deserialize(
      '{"Id":"a0L000000000009AAA","Name":"R-bare","CurrencyIsoCode":"USD"}',
      Restriction__c.class
    );
    RestrictionSummaryService svc = new RestrictionSummaryService();
    svc.selector = new MockSelector(bare);

    RestrictionSummaryResult r = svc.getSummary(null, 'a0L000000000009AAA');
    System.assertEquals(true, r.found);
    System.assert(
      r.resultsText.contains('Gift Commitment: Not linked'),
      'no commitment'
    );
    System.assert(
      r.resultsText.contains('Total Allocated (sum of yearly funds): N/A'),
      'no allocations'
    );
    System.assert(
      r.resultsText.contains('By Year: none recorded'),
      'no year lines'
    );
  }

  @isTest
  static void recordRefPopulatedAndTextClean() {
    RestrictionSummaryService svc = new RestrictionSummaryService();
    svc.selector = new MockSelector(sample());
    RestrictionSummaryResult r = svc.getSummary('x', null);
    System.assertNotEquals(null, r.record, 'record ref present');
    System.assertEquals(
      'Restriction__c',
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
      !t.contains('a0L000000000001AAA'),
      'no raw record id in resultsText'
    );
  }
}