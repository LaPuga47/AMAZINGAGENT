/**
 * Internal container of the raw records gathered for an Opportunity 360 summary.
 * Populated by the selector, consumed (and computed on) by the service. Not
 * exposed to the agent.
 */
public class OpportunitySummaryData {
    public Opportunity opp;
    public List<GiftCommitment> commitments = new List<GiftCommitment>();
    public List<GiftTransaction> transactions = new List<GiftTransaction>();
    public List<Restriction__c> restrictions = new List<Restriction__c>();
}