/**
 * Restriction business logic: delegates querying to the Selector, maps records to
 * FLS-safe RestrictionSummary DTOs, and ranks by relevance when a search term is
 * supplied. No SOQL/DML here. The selector is injectable for unit testing.
 */
public with sharing class RestrictionService implements IRestrictionService {
  @TestVisible
  private IRestrictionSelector selector = new RestrictionSelector();

  public List<RestrictionSummary> findRestrictions(
    String searchTerm,
    Id giftCommitmentId,
    Id opportunityId,
    String country,
    Integer maxResults
  ) {
    List<Restriction__c> records = selector.search(
      searchTerm,
      giftCommitmentId,
      opportunityId,
      country,
      maxResults
    );

    List<RestrictionSummary> summaries = new List<RestrictionSummary>();
    for (Restriction__c r : records) {
      summaries.add(toSummary(r));
    }

    if (String.isNotBlank(searchTerm)) {
      summaries = sortByRelevance(searchTerm, summaries);
    }
    return summaries;
  }

  private RestrictionSummary toSummary(Restriction__c r) {
    RestrictionSummary summary = new RestrictionSummary();
    summary.id = r.Id;
    summary.name = r.Name;
    summary.giftCommitmentName = r.Gift_Commitment__r == null
      ? null
      : r.Gift_Commitment__r.Name;
    summary.country = r.Restriction_Country__c;
    summary.staffOrOverhead = r.Staff_or_Overhead__c;
    summary.timeRestricted = r.Is_this_grant_time_restricted__c;
    summary.theme = r.Theme__c;
    summary.timeAllocation = r.Time_Allocation__c;
    summary.notes = r.Additional_Restriction_Notes__c;
    summary.record = new AgentRecordResult(r.Id, 'Restriction__c', r.Name)
      .withSubtitle(r.Restriction_Country__c)
      .withSummary(r.Theme__c);
    return summary;
  }

  private List<RestrictionSummary> sortByRelevance(
    String term,
    List<RestrictionSummary> items
  ) {
    List<RankedSummary> ranked = new List<RankedSummary>();
    for (RestrictionSummary item : items) {
      ranked.add(new RankedSummary(EntityMatcher.score(term, item.name), item));
    }
    ranked.sort();
    List<RestrictionSummary> ordered = new List<RestrictionSummary>();
    for (RankedSummary entry : ranked) {
      ordered.add(entry.summary);
    }
    return ordered;
  }

  /** Sorts by relevance score descending. */
  private class RankedSummary implements Comparable {
    private final Integer score;
    private final RestrictionSummary summary;

    private RankedSummary(Integer score, RestrictionSummary summary) {
      this.score = score;
      this.summary = summary;
    }

    public Integer compareTo(Object other) {
      return ((RankedSummary) other).score - this.score;
    }
  }
}