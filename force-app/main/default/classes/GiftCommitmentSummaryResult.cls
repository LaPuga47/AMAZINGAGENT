/**
 * Agent-facing result of a Gift Commitment 360. The rich, grounded summary is
 * carried in resultsText (built deterministically in Apex).
 */
public class GiftCommitmentSummaryResult {
  public Boolean found;
  public String commitmentName;
  public AgentRecordResult record;
  public String recordId;
  public String objectApiName;
  public String resultsText;
}