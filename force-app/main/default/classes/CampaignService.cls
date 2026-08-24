/**
 * Campaign business logic: delegates querying to the Selector, maps records to
 * FLS-safe CampaignSummary DTOs, and ranks by relevance when a search term is
 * supplied. No SOQL/DML here. The selector is injectable for unit testing.
 */
public with sharing class CampaignService implements ICampaignService {
  @TestVisible
  private ICampaignSelector selector = new CampaignSelector();

  public List<CampaignSummary> findCampaigns(
    String searchTerm,
    String status,
    Integer maxResults
  ) {
    List<Campaign> records = selector.search(searchTerm, status, maxResults);

    List<CampaignSummary> summaries = new List<CampaignSummary>();
    for (Campaign camp : records) {
      summaries.add(toSummary(camp));
    }

    if (String.isNotBlank(searchTerm)) {
      summaries = sortByRelevance(searchTerm, summaries);
    }
    return summaries;
  }

  private CampaignSummary toSummary(Campaign camp) {
    CampaignSummary summary = new CampaignSummary();
    summary.id = camp.Id;
    summary.name = camp.Name;
    summary.type = camp.Type;
    summary.status = camp.Status;
    summary.startDate = camp.StartDate;
    summary.endDate = camp.EndDate;
    summary.isActive = camp.IsActive;
    summary.ownerName = camp.Owner == null ? null : camp.Owner.Name;
    summary.record = new AgentRecordResult(camp.Id, 'Campaign', camp.Name).withSubtitle(camp.Status).withSummary(camp.Type);
    return summary;
  }

  private List<CampaignSummary> sortByRelevance(
    String term,
    List<CampaignSummary> items
  ) {
    List<RankedSummary> ranked = new List<RankedSummary>();
    for (CampaignSummary item : items) {
      ranked.add(new RankedSummary(EntityMatcher.score(term, item.name), item));
    }
    ranked.sort();
    List<CampaignSummary> ordered = new List<CampaignSummary>();
    for (RankedSummary entry : ranked) {
      ordered.add(entry.summary);
    }
    return ordered;
  }

  /** Sorts by relevance score descending. */
  private class RankedSummary implements Comparable {
    private final Integer score;
    private final CampaignSummary summary;

    private RankedSummary(Integer score, CampaignSummary summary) {
      this.score = score;
      this.summary = summary;
    }

    public Integer compareTo(Object other) {
      return ((RankedSummary) other).score - this.score;
    }
  }
}