/**
 * Selector contract for Campaign. All Campaign SOQL lives behind this so Services
 * can be unit-tested against a mock (no SOQL/DML in service tests).
 */
public interface ICampaignSelector {
    List<Campaign> search(String searchTerm, String status, Integer maxRecords);
}