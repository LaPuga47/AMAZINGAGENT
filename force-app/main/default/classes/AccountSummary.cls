/**
 * FLS-safe, agent-facing projection of an Account. Only these fields are exposed
 * to the agent/LLM — raw SObjects are never returned.
 */
public class AccountSummary {
  @InvocableVariable
  public String id;
  @InvocableVariable
  public String name;
  @InvocableVariable
  public String type;
  @InvocableVariable
  public String industry;
  @InvocableVariable
  public String phone;
  @InvocableVariable
  public String website;
  @InvocableVariable
  public String city;
  @InvocableVariable
  public String country;
  @InvocableVariable
  public String ownerName;

    @InvocableVariable
    public AgentRecordResult record;
}