/**
 * FLS-safe, agent-facing projection of a Restriction (custom Restriction__c).
 * Only these fields are exposed to the agent/LLM — raw SObjects are never returned.
 */
public class RestrictionSummary {
  @InvocableVariable
  public String id;
  @InvocableVariable
  public String name;
  @InvocableVariable
  public String giftCommitmentName;
  @InvocableVariable
  public String country;
  @InvocableVariable
  public String staffOrOverhead;
  @InvocableVariable
  public String timeRestricted;
  @InvocableVariable
  public String theme;
  @InvocableVariable
  public Decimal timeAllocation;
  @InvocableVariable
  public String notes;

    @InvocableVariable
    public AgentRecordResult record;
}