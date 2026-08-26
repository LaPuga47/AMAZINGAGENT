/**
 * FundingContext — the normalized funding graph around a starting record, assembled by
 * FundingContextService and rendered by AmaizeGetFundingContext. It holds the deduped
 * Salesforce records (Budget Lines and their allocations, each carrying its Restriction ->
 * Gift Commitment -> Opportunity -> Account lineage) plus scope, headroom, and data-quality
 * notes. Plain data holder — no SOQL, no DML.
 */
public with sharing class FundingContext {

    public enum Status { FOUND_BUDGET_LINE, FOUND_OPPORTUNITY, NEEDS_INFO, NOT_FOUND, AMBIGUOUS }
    public Status status;

    public String direction;                 // 'budget-line' | 'opportunity'
    public BudgetLineDimensions requested;
    public List<String> missingDimensions;
    public List<String> ambiguousChoices;    // names to disambiguate

    // Scope (budget-line direction) or focus (opportunity direction).
    public String country;
    public String businessUnit;
    public String fiscalYear;
    public String scenarioLabel;
    public Opportunity focusOpportunity;     // opportunity direction

    // The funding graph: Budget Lines in scope + the allocations linking funding to them.
    public List<Budget_Line__c> budgetLines = new List<Budget_Line__c>();
    public List<Allocation__c> allocations = new List<Allocation__c>();  // lineage anchor
    public String currencyIsoCode;

    // Headroom (budget-line direction), summed from stored fields.
    public Decimal budgetCost = 0;
    public Decimal securedFunding = 0;
    public Decimal securedHeadroom = 0;
    public Decimal combinedCompeting = 0;
    public Decimal probWeightedCompeting = 0;
    public Decimal potentialExcess = 0;
    public String severity;

    // Data-quality flags surfaced to the user (never fabricate to fill these).
    public Integer allocationsMissingGiftCommitment = 0;
    public Integer allocationsMissingRestriction = 0;
    public Integer allocationsUnlinkedToBudgetLine = 0;
    public Boolean viaMatchKey = false;      // some allocations resolved by Match Key, not direct link
}
