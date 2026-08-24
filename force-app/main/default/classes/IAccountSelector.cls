/**
 * Selector contract for Account. All Account SOQL lives behind this so Services
 * can be unit-tested against a mock (no SOQL/DML in service tests).
 */
public interface IAccountSelector {
    List<Account> search(String searchTerm, String accountType, Integer maxRecords);
}