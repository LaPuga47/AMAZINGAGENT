/**
 * FLS-safe, agent-facing projection of a GiftCommitment (pledge). Only these
 * fields are exposed to the agent/LLM — raw SObjects are never returned.
 */
public class GiftCommitmentSummary {
  @InvocableVariable
  public String id;
  @InvocableVariable
  public String name;
  @InvocableVariable
  public String status;
  @InvocableVariable
  public String donorName;
  @InvocableVariable
  public Decimal expectedTotalAmount;
  @InvocableVariable
  public String formattedExpectedTotal;
  @InvocableVariable
  public Decimal totalPaidAmount;
  @InvocableVariable
  public Decimal remainingBalance;
  @InvocableVariable
  public Date nextTransactionDate;
  @InvocableVariable
  public Decimal nextTransactionAmount;
  @InvocableVariable
  public Date startDate;
  @InvocableVariable
  public Date endDate;
  @InvocableVariable
  public String ownerName;

    @InvocableVariable
    public AgentRecordResult record;
}