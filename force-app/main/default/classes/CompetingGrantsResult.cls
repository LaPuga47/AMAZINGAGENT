/**
 * CompetingGrantsResult — the outcome of a governed competing-grants analysis. Carries the
 * SAME governed Headroom totals Headroom Analysis produces for the scope (so the two never
 * diverge), the qualifying Budget Line count, and the Opportunities competing for that
 * population with their allocation exposure. Plain data holder — no SOQL, no DML.
 */
public with sharing class CompetingGrantsResult {

    // FOUND / NONE (no qualifying lines) / ZERO (Unrestricted/Working Capital) /
    // NOT_CONFIGURED / NEEDS_INFO
    public enum Status { FOUND, NONE, ZERO, NOT_CONFIGURED, NEEDS_INFO }
    public Status status;

    public List<String> missing = new List<String>();

    // Governed scope (identical resolution to Headroom Analysis).
    public String category;
    public String country;
    public String fiscalYear;
    public String scenarioLabel;
    public Integer budgetLineCount = 0;
    public String currencyIsoCode;

    // Governed Headroom totals (summed across the qualifying Budget Lines' stored fields).
    public Decimal budgetAmount = 0;
    public Decimal securedFunding = 0;
    public Decimal likelyFunding = 0;
    public Decimal pipelineFunding = 0;
    public Decimal forecastFunding = 0;
    public Decimal securedHeadroom = 0;
    public Decimal forecastHeadroom = 0;
    public String headroomStatus;

    // Competing grants (grouped by Opportunity), most advanced first.
    public List<CompetingGrant> grants = new List<CompetingGrant>();

    // Exposure roll-up (competing = Likely + Pipeline).
    public Decimal combinedCompeting = 0;
    public Decimal combinedLikelyExposure = 0;
    public Decimal combinedPipelineExposure = 0;
    public Decimal probWeightedCompeting = 0;
    public Decimal potentialExcess = 0;
    public Decimal minimumAdjustmentRequired = 0;   // max(0, combinedCompeting - securedHeadroom)
    public String severity;

    // Analysis confidence (deterministic).
    public String analysisConfidence;               // High / Medium / Low
    public List<String> confidenceReasons = new List<String>();

    // "What can fit" scenarios (competing exposure vs secured headroom).
    public List<FitScenario> whatCanFit = new List<FitScenario>();
    public Boolean exhaustiveCombinations = false;   // true when all subsets enumerated

    // Coordination + timing + freshness context.
    public Integer distinctOwnerCount = 0;
    public String timingCollisionStatus;             // FY-grain (finer period data not in model)
    public Datetime retrievalTime;

    // Data quality.
    public Integer allocationsMissingGiftCommitment = 0;
    public Boolean noAllocations = false;   // governed lines found, but no allocations linked
    public Decimal unmappedOpportunityAmountTotal = 0;

    /** A "what can fit" combination: which opportunities, their combined exposure, fit/excess. */
    public class FitScenario {
        public String label;
        public Decimal exposure;
        public Boolean fits;
        public Decimal excess;   // amount over headroom when it does not fit (else 0)
        public FitScenario(String label, Decimal exposure, Decimal headroom) {
            this.label = label;
            this.exposure = exposure;
            this.fits = exposure <= headroom;
            this.excess = this.fits ? 0 : (exposure - headroom);
        }
    }

    /** True when two or more Opportunities have competing (Likely/Pipeline) exposure here. */
    public Boolean hasCompetition() {
        Integer n = 0;
        for (CompetingGrant g : grants) { if (g.isCompetingPipeline()) { n++; } }
        return n >= 2;
    }
}
