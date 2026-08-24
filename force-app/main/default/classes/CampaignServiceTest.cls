@isTest
private class CampaignServiceTest {
  private class MockSelector implements ICampaignSelector {
    private List<Campaign> toReturn;
    private MockSelector(List<Campaign> records) {
      this.toReturn = records;
    }
    public List<Campaign> search(
      String searchTerm,
      String status,
      Integer maxRecords
    ) {
      return toReturn;
    }
  }

  private static Campaign camp(String id, String name) {
    return (Campaign) JSON.deserialize(
      '{"Id":"' +
        id +
        '","Name":"' +
        name +
        '","Type":"Fundraising","Status":"In Progress",' +
        '"StartDate":"2026-01-01","EndDate":"2026-12-31","IsActive":true,"Owner":{"Name":"Jane Doe"}}',
      Campaign.class
    );
  }

  @isTest
  static void mapsRecordsToSummaries() {
    CampaignService svc = new CampaignService();
    svc.selector = new MockSelector(
      new List<Campaign>{ camp('701000000000001AAA', 'Year-End Appeal') }
    );

    List<CampaignSummary> results = svc.findCampaigns(null, null, null);

    System.assertEquals(1, results.size());
    CampaignSummary s = results[0];
    System.assertEquals('701000000000001AAA', s.id);
    System.assertEquals('Year-End Appeal', s.name);
    System.assertEquals('Fundraising', s.type);
    System.assertEquals('In Progress', s.status);
    System.assertEquals(true, s.isActive);
    System.assertEquals('Jane Doe', s.ownerName);
    System.assertEquals('701000000000001AAA', s.id, 'record Id populated');
  }

  @isTest
  static void ranksByRelevanceWhenSearchTermGiven() {
    CampaignService svc = new CampaignService();
    svc.selector = new MockSelector(
      new List<Campaign>{
        camp('701000000000001AAA', 'Alpha Drive'),
        camp('701000000000002AAA', 'Beta Appeal')
      }
    );

    List<CampaignSummary> results = svc.findCampaigns('beta', null, 10);

    System.assertEquals(2, results.size());
    System.assertEquals(
      'Beta Appeal',
      results[0].name,
      'Best match should rank first'
    );
  }

  @isTest
  static void returnsEmptyWhenNoRecords() {
    CampaignService svc = new CampaignService();
    svc.selector = new MockSelector(new List<Campaign>());

    List<CampaignSummary> results = svc.findCampaigns('anything', null, null);
    System.assertEquals(0, results.size());
  }
}