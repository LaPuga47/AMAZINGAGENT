/**
 * CompetingGrantsResult — the outcome of a competing-grants analysis for a funding scope.
 * Carries the scope, its headroom, the grants competing for it, the combined exposure, and
 * a severity classification. Plain data holder — no SOQL, no DML.
 */
public with sharing class CompetingGrantsResult {

    public enum Status { FOUND, NOT_FOUND, NEEDS_INFO }
    public Status status;

    public BudgetLineDimensions requested;
    public List<String> missingDimensions;

    // Scope description (rolled up across the matched Budget Lines).
    public String country;
    public String businessUnit;
    public String fiscalYear;
    public String scenarioLabel;
    public Integer lineCount = 0;
    public String currencyIsoCode;

    // Headroom for the scope (summed from the matched Budget Lines' stored figures).
    public Decimal budgetCost = 0;
    public Decimal securedFunding = 0;
    public Decimal likelyFunding = 0;
    public Decimal pipelineFunding = 0;
    public Decimal securedHeadroom = 0;   // budget - secured
    public Decimal forecastHeadroom = 0;  // budget - secured - likely - pipeline

    // Competing grants (grouped by Opportunity), most advanced first.
    public List<CompetingGrant> grants = new List<CompetingGrant>();

    // Exposure.
    public Decimal combinedCompeting = 0;     // Σ competing (Likely+Pipeline) allocated amounts
    public Decimal probWeightedCompeting = 0; // Σ probability-weighted competing amounts
    public Decimal potentialExcess = 0;       // combinedCompeting - securedHeadroom

    // Severity: No Material / Moderate / High / Critical.
    public String severity;

    /** True when there is more than one grant genuinely competing for the scope. */
    public Boolean hasCompetition() {
        Integer competing = 0;
        for (CompetingGrant g : grants) {
            if (g.isCompetingPipeline()) { competing++; }
        }
        return competing >= 2;
    }
}
