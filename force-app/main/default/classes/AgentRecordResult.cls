/**
 * Shared, cross-domain structured record-navigation contract surfaced by every
 * Employee Agent action (Opportunity, Account, Campaign, Gift Commitment, Gift
 * Transaction, Restriction).
 *
 * The custom Lightning Type renderer builds navigation from recordId +
 * objectApiName (NavigationMixin) — no URL is ever produced, so the Einstein
 * Trust Layer URL masking never applies. recordName / subtitle / summary drive an
 * executive-friendly card. This object carries the Id as structured data only; a
 * record Id or URL must never be placed into agent-visible text (resultsText).
 */
public class AgentRecordResult {
  @AuraEnabled
  public String recordId;
  @AuraEnabled
  public String objectApiName;
  @AuraEnabled
  public String recordName;
  @AuraEnabled
  public String subtitle;
  @AuraEnabled
  public String summary;

  public AgentRecordResult() {
  }

  public AgentRecordResult(
    Id recordId,
    String objectApiName,
    String recordName
  ) {
    this.recordId = recordId == null ? null : String.valueOf(recordId);
    this.objectApiName = objectApiName;
    this.recordName = recordName;
  }

  public AgentRecordResult withSubtitle(String value) {
    this.subtitle = String.isBlank(value) ? null : value;
    return this;
  }

  public AgentRecordResult withSummary(String value) {
    this.summary = String.isBlank(value) ? null : value;
    return this;
  }
}