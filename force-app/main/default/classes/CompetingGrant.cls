/**
 * CompetingGrant — one grant Opportunity competing for a governed Headroom population, with
 * its exposure = the SUM of its Funding Allocations against the qualifying Budget Lines (never
 * the whole Opportunity Amount), broken down by allocation type. Allocation-level detail is
 * retained so the agent can explain and link the underlying records.
 *
 * Plain data holder — no SOQL, no DML.
 */
public with sharing class CompetingGrant {

    public Id opportunityId;
    public String opportunityName;
    public Id accountId;            // donor
    public String donorName;
    public String owner;            // Opportunity.Guardian__c
    public String stage;
    public Decimal probability;
    public Date closeDate;
    public Decimal opportunityAmount;   // fundraising context only — NOT the exposure
    public String currencyIsoCode;

    // Exposure to THIS governed scope (summed allocation amounts), split by type.
    public Decimal allocatedAmount = 0;
    public Decimal probWeightedAmount = 0;
    public Decimal securedExposure = 0;
    public Decimal likelyExposure = 0;
    public Decimal pipelineExposure = 0;

    public Boolean hasApproved = false;
    public Boolean onlyUnconfirmed = true;   // only Draft/Suggested -> low confidence

    public Integer allocationCount = 0;
    public Set<Id> budgetLineIds = new Set<Id>();
    public Set<Id> restrictionIds = new Set<Id>();
    public List<Allocation__c> allocations = new List<Allocation__c>();  // detail for drill-down/links

    // Allocation coverage (computed once all allocations for the opportunity are known).
    public Decimal totalMappedAllocation = 0;   // this opp's allocations across ALL scopes
    public Decimal exposureElsewhere = 0;       // totalMapped - allocatedAmount(this scope)
    public Decimal unmappedAmount;              // opportunityAmount - totalMapped (null if not computable)
    public Decimal allocationCoveragePct;       // totalMapped / opportunityAmount (null if no amount)
    public Decimal headroomConsumptionPct;      // allocatedAmount / secured headroom of the scope
    public Datetime lastModifiedDate;

    /** The competing (not-yet-secured) portion: has any Likely or Pipeline allocation. */
    public Boolean isCompetingPipeline() {
        return likelyExposure > 0 || pipelineExposure > 0;
    }

    /** Fold one allocation for this scope into the grant's exposure. */
    public void addAllocation(Allocation__c a, Decimal amount, Decimal probWeighted) {
        allocations.add(a);
        allocationCount++;
        allocatedAmount += amount;
        probWeightedAmount += probWeighted;
        if (a.Budget_Line__c != null) { budgetLineIds.add(a.Budget_Line__c); }
        if (a.Restriction__c != null) { restrictionIds.add(a.Restriction__c); }
        String type = a.Allocation_Type__c;
        if (type == 'Secured') { securedExposure += amount; }
        else if (type == 'Likely') { likelyExposure += amount; }
        else if (type == 'Pipeline') { pipelineExposure += amount; }
        String stat = a.Allocation_Status__c;
        if (stat == 'Approved' || stat == 'Released') { hasApproved = true; onlyUnconfirmed = false; }
    }
}
