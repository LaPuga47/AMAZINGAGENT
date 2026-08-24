/**
 * Agent-facing result of an Opportunity 360 summary. The rich, grounded summary
 * is carried in resultsText (built deterministically in Apex).
 */
public class OpportunitySummaryResult {
  public Boolean found;
  public String opportunityName;
  public AgentRecordResult record;
  public String recordId;
  public String objectApiName;
  public String resultsText;
}