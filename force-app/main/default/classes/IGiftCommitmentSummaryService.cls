/**
 * Service contract for the Gift Commitment 360. The Agent Action depends on this
 * interface (not the concrete class) so it can be unit-tested with a mock.
 */
public interface IGiftCommitmentSummaryService {
    GiftCommitmentSummaryResult getSummary(String searchTerm, Id commitmentId);
}