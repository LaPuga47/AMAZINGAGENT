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
}
