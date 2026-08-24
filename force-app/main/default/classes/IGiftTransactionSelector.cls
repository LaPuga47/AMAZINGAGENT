/**
 * Selector contract for GiftTransaction. All GiftTransaction SOQL lives behind
 * this so Services can be unit-tested against a mock (no SOQL/DML in service tests).
 */
public interface IGiftTransactionSelector {
    List<GiftTransaction> search(
        String searchTerm,
        Id donorId,
        Id giftCommitmentId,
        Id campaignId,
        String status,
        Integer maxRecords
    );
}