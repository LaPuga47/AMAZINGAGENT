/**
 * GiftTransaction business logic: delegates querying to the Selector, maps records
 * to FLS-safe GiftTransactionSummary DTOs, and ranks by relevance when a search
 * term is supplied. No SOQL/DML here. The selector is injectable for unit testing.
 */
public with sharing class GiftTransactionService implements IGiftTransactionService {
  @TestVisible
  private IGiftTransactionSelector selector = new GiftTransactionSelector();

  public List<GiftTransactionSummary> findGiftTransactions(
    String searchTerm,
    Id donorId,
    Id giftCommitmentId,
    Id campaignId,
    String status,
    Integer maxResults
  ) {
    List<GiftTransaction> records = selector.search(
      searchTerm,
      donorId,
      giftCommitmentId,
      campaignId,
      status,
      maxResults
    );

    List<GiftTransactionSummary> summaries = new List<GiftTransactionSummary>();
    for (GiftTransaction gt : records) {
      summaries.add(toSummary(gt));
    }

    if (String.isNotBlank(searchTerm)) {
      summaries = sortByRelevance(searchTerm, summaries);
    }
    return summaries;
  }

  private GiftTransactionSummary toSummary(GiftTransaction gt) {
    GiftTransactionSummary summary = new GiftTransactionSummary();
    summary.id = gt.Id;
    summary.name = gt.Name;
    summary.status = gt.Status;
    summary.transactionDate = gt.TransactionDate;
    summary.originalAmount = gt.OriginalAmount;
    summary.currentAmount = gt.CurrentAmount;
    summary.formattedAmount = FormatUtils.formatAmount(gt.CurrentAmount);
    summary.paymentMethod = gt.PaymentMethod;
    summary.giftType = gt.GiftType;
    summary.donorName = gt.Donor == null ? null : gt.Donor.Name;
    summary.giftCommitmentName = gt.GiftCommitment == null
      ? null
      : gt.GiftCommitment.Name;
    summary.campaignName = gt.Campaign == null ? null : gt.Campaign.Name;
    summary.record = new AgentRecordResult(gt.Id, 'GiftTransaction', gt.Name)
      .withSubtitle(gt.Status)
      .withSummary(FormatUtils.formatAmount(gt.CurrentAmount));
    return summary;
  }

  private List<GiftTransactionSummary> sortByRelevance(
    String term,
    List<GiftTransactionSummary> items
  ) {
    List<RankedSummary> ranked = new List<RankedSummary>();
    for (GiftTransactionSummary item : items) {
      ranked.add(new RankedSummary(EntityMatcher.score(term, item.name), item));
    }
    ranked.sort();
    List<GiftTransactionSummary> ordered = new List<GiftTransactionSummary>();
    for (RankedSummary entry : ranked) {
      ordered.add(entry.summary);
    }
    return ordered;
  }

  /** Sorts by relevance score descending. */
  private class RankedSummary implements Comparable {
    private final Integer score;
    private final GiftTransactionSummary summary;

    private RankedSummary(Integer score, GiftTransactionSummary summary) {
      this.score = score;
      this.summary = summary;
    }

    public Integer compareTo(Object other) {
      return ((RankedSummary) other).score - this.score;
    }
  }
}