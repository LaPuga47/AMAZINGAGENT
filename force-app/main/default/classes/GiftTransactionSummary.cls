/**
 * FLS-safe, agent-facing projection of a GiftTransaction (standard Nonprofit
 * Cloud object). Only these fields are exposed to the agent/LLM — raw SObjects
 * are never returned.
 */
public class GiftTransactionSummary {
  @InvocableVariable
  public String id;
  @InvocableVariable
  public String name;
  @InvocableVariable
  public String status;
  @InvocableVariable
  public Date transactionDate;
  @InvocableVariable
  public Decimal originalAmount;
  @InvocableVariable
  public Decimal currentAmount;
  @InvocableVariable
  public String formattedAmount;
  @InvocableVariable
  public String paymentMethod;
  @InvocableVariable
  public String giftType;
  @InvocableVariable
  public String donorName;
  @InvocableVariable
  public String giftCommitmentName;
  @InvocableVariable
  public String campaignName;
  @InvocableVariable
  public AgentRecordResult record;
}