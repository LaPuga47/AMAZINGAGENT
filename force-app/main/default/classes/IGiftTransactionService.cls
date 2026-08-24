/**
 * Service contract for the GiftTransaction domain. The Agent Action depends on
 * this interface (not the concrete class) so it can be unit-tested with a mock.
 */
public interface IGiftTransactionService {
    List<GiftTransactionSummary> findGiftTransactions(
        String searchTerm,
        Id donorId,
        Id giftCommitmentId,
        Id campaignId,
        String status,
        Integer maxResults
    );
}