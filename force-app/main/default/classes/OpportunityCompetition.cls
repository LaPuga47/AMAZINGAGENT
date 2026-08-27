/**
 * OpportunityCompetition — the result of an Opportunity-start competition analysis: the focus
 * grant, and for EACH governed Headroom scope its allocations touch, the governed competition
 * for that scope (so a multi-scope opportunity is analyzed per scope, never collapsed).
 * Plain data holder — no SOQL, no DML.
 */
public with sharing class OpportunityCompetition {

    public enum Status { FOUND, NOT_FOUND, AMBIGUOUS, NO_ALLOCATIONS, NEEDS_INFO }
    public Status status;

    // Focus opportunity.
    public Id opportunityId;
    public String opportunityName;
    public Id accountId;
    public String donorName;
    public String owner;
    public String stage;
    public Decimal opportunityAmount;
    public String currencyIsoCode;

    public List<String> ambiguousChoices;      // when the name matched more than one grant
    public Integer scopesTouched = 0;           // total governed scopes the opp touches
    public Boolean capped = false;              // more scopes than analyzed

    public List<ScopeCompetition> scopes = new List<ScopeCompetition>();

    /** One affected governed scope: the focus opp's exposure to it + the governed competition. */
    public class ScopeCompetition {
        public String category;
        public String country;
        public String fiscalYear;
        public Decimal focusExposure;           // the focus opp's allocation exposure to this scope
        public CompetingGrantsResult competition;  // full governed competition for the scope
        public ScopeCompetition(String category, String country, String fiscalYear,
                Decimal focusExposure, CompetingGrantsResult competition) {
            this.category = category;
            this.country = country;
            this.fiscalYear = fiscalYear;
            this.focusExposure = focusExposure;
            this.competition = competition;
        }
    }
}
