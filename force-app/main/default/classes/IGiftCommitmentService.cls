/**
 * Service contract for the GiftCommitment domain. The Agent Action depends on
 * this interface (not the concrete class) so it can be unit-tested with a mock.
 */
public interface IGiftCommitmentService {
    List<GiftCommitmentSummary> findGiftCommitments(String searchTerm, Id donorId, String status, Integer maxResults);
}