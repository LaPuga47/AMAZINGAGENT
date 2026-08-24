@isTest
private class RestrictionServiceTest {
  private class MockSelector implements IRestrictionSelector {
    private List<Restriction__c> toReturn;
    private MockSelector(List<Restriction__c> records) {
      this.toReturn = records;
    }
    public List<Restriction__c> search(
      String searchTerm,
      Id giftCommitmentId,
      Id opportunityId,
      String country,
      Integer maxRecords
    ) {
      return toReturn;
    }
  }

  private static Restriction__c rest(String id, String name) {
    return (Restriction__c) JSON.deserialize(
      '{"Id":"' +
        id +
        '","Name":"' +
        name +
        '","Restriction_Country__c":"Rwanda",' +
        '"Staff_or_Overhead__c":"Staff","Is_this_grant_time_restricted__c":"Yes",' +
        '"Theme__c":"Agriculture","Time_Allocation__c":75,' +
        '"Additional_Restriction_Notes__c":"For seed programs only",' +
        '"Gift_Commitment__r":{"Name":"Multi-Year Pledge"}}',
      Restriction__c.class
    );
  }

  @isTest
  static void mapsRecordsToSummaries() {
    RestrictionService svc = new RestrictionService();
    svc.selector = new MockSelector(
      new List<Restriction__c>{
        rest('a0L000000000001AAA', 'Seed Program Restriction')
      }
    );

    List<RestrictionSummary> results = svc.findRestrictions(
      null,
      null,
      null,
      null,
      null
    );

    System.assertEquals(1, results.size());
    RestrictionSummary s = results[0];
    System.assertEquals('Seed Program Restriction', s.name);
    System.assertEquals('Multi-Year Pledge', s.giftCommitmentName);
    System.assertEquals('Rwanda', s.country);
    System.assertEquals('Staff', s.staffOrOverhead);
    System.assertEquals('Yes', s.timeRestricted);
    System.assertEquals('Agriculture', s.theme);
    System.assertEquals(75, s.timeAllocation);
    System.assertEquals('a0L000000000001AAA', s.id, 'record Id populated');
  }

  @isTest
  static void ranksByRelevanceWhenSearchTermGiven() {
    RestrictionService svc = new RestrictionService();
    svc.selector = new MockSelector(
      new List<Restriction__c>{
        rest('a0L000000000001AAA', 'Alpha Restriction'),
        rest('a0L000000000002AAA', 'Beta Restriction')
      }
    );

    List<RestrictionSummary> results = svc.findRestrictions(
      'beta',
      null,
      null,
      null,
      10
    );

    System.assertEquals(2, results.size());
    System.assertEquals(
      'Beta Restriction',
      results[0].name,
      'Best match should rank first'
    );
  }

  @isTest
  static void returnsEmptyWhenNoRecords() {
    RestrictionService svc = new RestrictionService();
    svc.selector = new MockSelector(new List<Restriction__c>());

    List<RestrictionSummary> results = svc.findRestrictions(
      'anything',
      null,
      null,
      null,
      null
    );
    System.assertEquals(0, results.size());
  }
}