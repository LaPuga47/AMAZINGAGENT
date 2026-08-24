/**
 * Internal container of the raw records gathered for a Gift Commitment 360.
 * Populated by the selector, consumed by the service. Not exposed to the agent.
 */
public class GiftCommitmentSummaryData {
    public GiftCommitment commitment;
    public List<GiftTransaction> transactions = new List<GiftTransaction>();
    public List<Restriction__c> restrictions = new List<Restriction__c>();
}