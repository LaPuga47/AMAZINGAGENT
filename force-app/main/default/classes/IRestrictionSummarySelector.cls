/**
 * Selector contract for the Restriction 360. Returns the Restriction__c (with its
 * parent commitment context and yearly allocation fields) so the service can be
 * unit-tested with a mock (no SOQL/DML in the service test).
 */
public interface IRestrictionSummarySelector {
    Restriction__c fetch(String searchTerm, Id restrictionId);
}