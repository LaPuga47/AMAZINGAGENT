/**
 * Selector contract for the Account 360 summary. Gathers the Account and its
 * related contacts, opportunities, and gift records so the service can be
 * unit-tested with a mock (no SOQL/DML in the service test).
 */
public interface IAccountSummarySelector {
    AccountSummaryData fetch(String searchTerm, Id accountId);
}