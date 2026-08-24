/**
 * FLS-safe, agent-facing projection of an Opportunity. Only these fields are
 * exposed to the agent/LLM — raw SObjects are never returned. @InvocableVariable
 * makes each field readable by Agentforce.
 */
public class OpportunitySummary {
  @InvocableVariable
  public String id;
  @InvocableVariable
  public String name;
  @InvocableVariable
  public String stage;
  @InvocableVariable
  public Decimal amount;
  @InvocableVariable
  public String formattedAmount;
  @InvocableVariable
  public Date closeDate;
  @InvocableVariable
  public String accountName;
  @InvocableVariable
  public String ownerName;

    @InvocableVariable
    public AgentRecordResult record;
}