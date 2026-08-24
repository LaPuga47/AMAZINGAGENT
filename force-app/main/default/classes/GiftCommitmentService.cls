/**
 * GiftCommitment business logic: delegates querying to the Selector, maps records
 * to FLS-safe GiftCommitmentSummary DTOs, and ranks by relevance when a search
 * term is supplied. No SOQL/DML here. The selector is injectable for unit testing.
 */
public with sharing class GiftCommitmentService implements IGiftCommitmentService {
  @TestVisible
  private IGiftCommitmentSelector selector = new GiftCommitmentSelector();

  public List<GiftCommitmentSummary> findGiftCommitments(
    String searchTerm,
    Id donorId,
    String status,
    Integer maxResults
  ) {
    List<GiftCommitment> records = selector.search(
      searchTerm,
      donorId,
      status,
      maxResults
    );

    List<GiftCommitmentSummary> summaries = new List<GiftCommitmentSummary>();
    for (GiftCommitment gc : records) {
      summaries.add(toSummary(gc));
    }

    if (String.isNotBlank(searchTerm)) {
      summaries = sortByRelevance(searchTerm, summaries);
    }
    return summaries;
  }

  private GiftCommitmentSummary toSummary(GiftCommitment gc) {
    GiftCommitmentSummary summary = new GiftCommitmentSummary();
    summary.id = gc.Id;
    summary.name = gc.Name;
    summary.status = gc.Status;
    summary.donorName = gc.Donor == null ? null : gc.Donor.Name;
    summary.expectedTotalAmount = gc.ExpectedTotalCmtAmount;
    summary.formattedExpectedTotal = FormatUtils.formatAmount(
      gc.ExpectedTotalCmtAmount
    );
    summary.totalPaidAmount = gc.TotalPaidTransactionAmount;
    summary.remainingBalance = gc.Remaining_Balance__c;
    summary.nextTransactionDate = gc.NextTransactionDate;
    summary.nextTransactionAmount = gc.NextTransactionAmount;
    summary.startDate = gc.EffectiveStartDate;
    summary.endDate = gc.ExpectedEndDate;
    summary.ownerName = gc.Owner == null ? null : gc.Owner.Name;
    summary.record = new AgentRecordResult(gc.Id, 'GiftCommitment', gc.Name).withSubtitle(gc.Status).withSummary(FormatUtils.formatAmount(gc.ExpectedTotalCmtAmount));
    return summary;
  }

  private List<GiftCommitmentSummary> sortByRelevance(
    String term,
    List<GiftCommitmentSummary> items
  ) {
    List<RankedSummary> ranked = new List<RankedSummary>();
    for (GiftCommitmentSummary item : items) {
      ranked.add(new RankedSummary(EntityMatcher.score(term, item.name), item));
    }
    ranked.sort();
    List<GiftCommitmentSummary> ordered = new List<GiftCommitmentSummary>();
    for (RankedSummary entry : ranked) {
      ordered.add(entry.summary);
    }
    return ordered;
  }

  /** Sorts by relevance score descending. */
  private class RankedSummary implements Comparable {
    private final Integer score;
    private final GiftCommitmentSummary summary;

    private RankedSummary(Integer score, GiftCommitmentSummary summary) {
      this.score = score;
      this.summary = summary;
    }

    public Integer compareTo(Object other) {
      return ((RankedSummary) other).score - this.score;
    }
  }
}