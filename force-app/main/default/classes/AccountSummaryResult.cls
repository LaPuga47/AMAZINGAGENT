/**
 * Agent-facing result of an Account 360 summary. The rich, grounded summary is
 * carried in resultsText (built deterministically in Apex).
 */
public class AccountSummaryResult {
  public Boolean found;
  public String accountName;
  public AgentRecordResult record;
  public String recordId;
  public String objectApiName;
  // Deterministic classification (Phase 2 contract)
  public String accountCategory;
  public String recordTypeName;
  public String recordTypeDeveloperName;
  public Boolean isPersonAccount;
  public String accountType;
  public String donorType;
  public String donorStatus;
  public String accountGuardian;
  public String ownerName;
  // Clickable related-people cards (contacts / affiliations, navigable by Id).
  public List<AgentRecordResult> records = new List<AgentRecordResult>();
  public String resultsText;
}