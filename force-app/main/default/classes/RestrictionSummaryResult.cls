/**
 * Agent-facing result of a Restriction 360. The rich, grounded summary is carried
 * in resultsText (built deterministically in Apex).
 */
public class RestrictionSummaryResult {
  public Boolean found;
  public String restrictionName;
  public AgentRecordResult record;
  public String recordId;
  public String objectApiName;
  public String resultsText;
}