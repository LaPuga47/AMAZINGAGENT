/**
 * IBudgetLineSelector — read-only query surface for Budget_Line__c, so the Headroom
 * service can be unit-tested against a stub. All implementations run in user mode.
 */
public interface IBudgetLineSelector {

    /** Budget Lines in the current scenario whose composite unique key equals `key`. */
    List<Budget_Line__c> findByUniqueKey(String key);

    /** Budget Lines in the current scenario matching every supplied (non-null) dimension. */
    List<Budget_Line__c> findByDimensions(BudgetLineDimensions dimensions);

    /** Budget Lines in the current scenario, optionally scoped by country and/or fiscal year. */
    List<Budget_Line__c> findPortfolio(String country, String fiscalYear);

    /** Budget Lines by record Id (any scenario) — used to resolve lines an allocation points to. */
    List<Budget_Line__c> byIds(Set<Id> ids);

    /** Aggregate the governed financial fields (SUM) + line count across a category population. */
    AggregateResult aggregateScope(BudgetLineDimensions dimensions);

    /** The complete governed Budget Line population (all qualifying records) for a category scope. */
    List<Budget_Line__c> findByGovernedScope(BudgetLineDimensions dimensions);

    /** Portfolio rollup: governed fields grouped by Country/BusinessUnit/Department/FiscalYear. */
    List<AggregateResult> aggregatePortfolio(String country, String fiscalYear);

    /**
     * The distinct fiscal years present in the current-scenario Budget Lines for a country,
     * ascending. Lets the next-available-year lookahead search only years that actually have
     * planning data (no hard-coded horizon).
     */
    List<String> distinctFiscalYears(String country);

    /**
     * Which Budget Line dimension fields (Department / Cost Category / Cost Type / Sub-Unit)
     * carry the given value within the current-scenario population for a country/fiscal year.
     * Used to auto-detect the dimension of an explicit value and to flag ambiguity.
     */
    Set<String> dimensionsContaining(String value, String country, String fiscalYear);
}
