/**
 * CompetingGrant — one grant Opportunity competing for a funding scope, with the amount
 * that actually competes (the ALLOCATED amount for this scope, not the whole Opportunity
 * Amount) and the certainty of that funding.
 *
 * Plain data holder — no SOQL, no DML.
 */
public with sharing class CompetingGrant {

    public Id opportunityId;
    public String opportunityName;
    public String donor;            // funder Account name
    public String owner;            // Opportunity.Guardian__c (the RM)
    public String stage;
    public Decimal probability;
    public Date closeDate;
    public String currencyIsoCode;

    // The amount competing for THIS scope: the sum of its allocations here (never the raw
    // Opportunity.Amount), so overlapping/partial funding is not double-counted.
    public Decimal allocatedAmount = 0;
    public Decimal probWeightedAmount = 0;

    // Funding certainty for this scope, from Allocation_Type__c across its allocations here.
    public Boolean hasSecured = false;   // Secured / Released -> already consumes headroom
    public Boolean hasLikely = false;    // Likely            -> competing pipeline
    public Boolean hasPipeline = false;  // Pipeline          -> competing pipeline
    public Boolean hasApproved = false;  // any Approved/Released allocation
    public Boolean onlyUnconfirmed = true; // only Draft/Suggested/Cancelled -> low confidence

    /** The competing (not-yet-secured) portion: Likely + Pipeline allocations only. */
    public Boolean isCompetingPipeline() {
        return hasLikely || hasPipeline;
    }
}
