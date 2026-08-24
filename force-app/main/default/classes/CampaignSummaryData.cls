/**
 * Internal container of the aggregates gathered for a Campaign Performance 360.
 * Executive-friendly: totals, counts, and status breakdowns only — no
 * per-record lists. Populated by the selector, consumed by the service.
 */
public class CampaignSummaryData {
    public Campaign camp;

    // Opportunity pipeline (live aggregate; rollup counts/amounts live on camp).
    public Decimal openPipelineAmount;
    public Integer openOpportunityCount;

    // Gift transactions attributed to the campaign (directly or via a linked commitment).
    public Decimal giftReceivedAmount;         // sum of Paid CurrentAmount
    public Integer paidGiftTransactionCount;   // count of Paid
    public Integer totalGiftTransactionCount;  // count of all
    public Map<String, Integer> giftCountByStatus = new Map<String, Integer>();
    public Map<String, Decimal> giftAmountByStatus = new Map<String, Decimal>();

    // Campaign members.
    public Integer memberCount;
    public Integer respondedMemberCount;
    public Map<String, Integer> memberStatusCounts = new Map<String, Integer>();
}