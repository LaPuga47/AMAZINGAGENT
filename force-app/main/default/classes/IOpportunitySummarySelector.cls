/**
 * Selector contract for the Opportunity 360 summary. Gathers the Opportunity and
 * its related gift records in one place so the service can be unit-tested with a
 * mock (no SOQL/DML in the service test).
 */
public interface IOpportunitySummarySelector {
    OpportunitySummaryData fetch(String searchTerm, Id opportunityId);
}