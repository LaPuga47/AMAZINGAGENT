/**
 * Agent-facing result of a Campaign Performance 360. The rich, grounded summary
 * is carried in resultsText (built deterministically in Apex).
 */
public class CampaignSummaryResult {
  public Boolean found;
  public String campaignName;
  public AgentRecordResult record;
  public String recordId;
  public String objectApiName;
  public String resultsText;
}