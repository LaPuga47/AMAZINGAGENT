/**
 * Opportunity business logic: delegates querying to the Selector, maps records
 * to FLS-safe OpportunitySummary DTOs, and ranks by relevance when a search term
 * is supplied. No SOQL/DML here. The selector is injectable for unit testing.
 */
public with sharing class OpportunityService implements IOpportunityService {
  @TestVisible
  private IOpportunitySelector selector = new OpportunitySelector();

  public List<OpportunitySummary> findOpportunities(
    String searchTerm,
    Id accountId,
    String stage,
    Integer maxResults
  ) {
    List<Opportunity> records = selector.search(
      searchTerm,
      accountId,
      stage,
      maxResults
    );

    List<OpportunitySummary> summaries = new List<OpportunitySummary>();
    for (Opportunity opp : records) {
      summaries.add(toSummary(opp));
    }

    if (String.isNotBlank(searchTerm)) {
      summaries = sortByRelevance(searchTerm, summaries);
    }
    return summaries;
  }

  private OpportunitySummary toSummary(Opportunity opp) {
    OpportunitySummary summary = new OpportunitySummary();
    summary.id = opp.Id;
    summary.name = opp.Name;
    summary.stage = opp.StageName;
    summary.amount = opp.Amount;
    summary.formattedAmount = FormatUtils.formatAmount(opp.Amount);
    summary.closeDate = opp.CloseDate;
    summary.accountName = opp.Account == null ? null : opp.Account.Name;
    summary.ownerName = opp.Owner == null ? null : opp.Owner.Name;
    summary.record = new AgentRecordResult(opp.Id, 'Opportunity', opp.Name).withSubtitle(opp.StageName).withSummary(FormatUtils.formatAmount(opp.Amount));
    return summary;
  }

  private List<OpportunitySummary> sortByRelevance(
    String term,
    List<OpportunitySummary> items
  ) {
    List<RankedSummary> ranked = new List<RankedSummary>();
    for (OpportunitySummary item : items) {
      ranked.add(new RankedSummary(EntityMatcher.score(term, item.name), item));
    }
    ranked.sort();
    List<OpportunitySummary> ordered = new List<OpportunitySummary>();
    for (RankedSummary entry : ranked) {
      ordered.add(entry.summary);
    }
    return ordered;
  }

  /** Sorts by relevance score descending. */
  private class RankedSummary implements Comparable {
    private final Integer score;
    private final OpportunitySummary summary;

    private RankedSummary(Integer score, OpportunitySummary summary) {
      this.score = score;
      this.summary = summary;
    }

    public Integer compareTo(Object other) {
      return ((RankedSummary) other).score - this.score;
    }
  }
}