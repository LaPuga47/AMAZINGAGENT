/**
 * Selector contract for GiftCommitment. All GiftCommitment SOQL lives behind this
 * so Services can be unit-tested against a mock (no SOQL/DML in service tests).
 */
public interface IGiftCommitmentSelector {
    List<GiftCommitment> search(String searchTerm, Id donorId, String status, Integer maxRecords);
}