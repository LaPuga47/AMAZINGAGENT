/**
 * FLS-safe, agent-facing projection of a Campaign. Only these fields are exposed
 * to the agent/LLM — raw SObjects are never returned.
 */
public class CampaignSummary {
  @InvocableVariable
  public String id;
  @InvocableVariable
  public String name;
  @InvocableVariable
  public String type;
  @InvocableVariable
  public String status;
  @InvocableVariable
  public Date startDate;
  @InvocableVariable
  public Date endDate;
  @InvocableVariable
  public Boolean isActive;
  @InvocableVariable
  public String ownerName;

    @InvocableVariable
    public AgentRecordResult record;
}