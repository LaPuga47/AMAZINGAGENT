/**
 * HeadroomAggregate — the governed Headroom aggregation result for a category / country /
 * fiscal year. Carries the eight required financial figures (summed across all qualifying
 * Budget Lines), the line count, the derived Headroom Status, and a state so the caller can
 * render the right message. Plain data holder — no SOQL, no DML.
 */
public with sharing class HeadroomAggregate {

    // FOUND         - qualifying lines summed
    // NONE          - no qualifying Budget Lines for the scope (NOT a zero financial value)
    // ZERO          - governed zero category (Unrestricted / Working Capital)
    // NOT_CONFIGURED- category has no governed Salesforce aggregation rule yet
    // NEEDS_INFO    - missing category/country/fiscal year
    // AMBIGUOUS     - a dimension VALUE was named that exists in more than one Budget Line dimension
    // NOT_FOUND     - a dimension value was named that exists in no available Budget Line dimension
    public enum State { FOUND, NONE, ZERO, NOT_CONFIGURED, NEEDS_INFO, AMBIGUOUS, NOT_FOUND }
    public State state;

    public String category;      // canonical Headroom category label (Program), or the dimension value (Dimension Mode)
    public String country;
    public String fiscalYear;
    public String scenarioLabel; // the Budget Scenario the current-scenario lines belong to
    public List<String> missing = new List<String>();
    public String currencyIsoCode;

    // Dimension Mode: the value looked up (e.g. "Crop Insurance") and, when ambiguous, the
    // candidate dimension names it matched (e.g. Cost Type / Cost Category).
    public String dimensionValue;
    public List<String> candidateDimensions = new List<String>();

    // The eight governed financial fields (summed; Budget Amount presented as positive cost).
    public Decimal budgetAmount = 0;
    public Decimal securedFunding = 0;
    public Decimal likelyFunding = 0;
    public Decimal pipelineFunding = 0;
    public Decimal forecastFunding = 0;
    public Decimal securedHeadroom = 0;
    public Decimal forecastHeadroom = 0;
    public String headroomStatus;   // status field — derived, never summed

    public Integer budgetLinesIncluded = 0;
}
