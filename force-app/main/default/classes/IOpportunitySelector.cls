/**
 * Selector contract for Opportunity. All Opportunity SOQL lives behind this so
 * Services can be unit-tested against a mock (no SOQL/DML in service tests).
 */
public interface IOpportunitySelector {
    List<Opportunity> search(String searchTerm, Id accountId, String stage, Integer maxRecords);
}