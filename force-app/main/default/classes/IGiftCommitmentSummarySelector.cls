/**
 * Selector contract for the Gift Commitment 360. Gathers the commitment and its
 * related transactions and restrictions so the service can be unit-tested with a
 * mock (no SOQL/DML in the service test).
 */
public interface IGiftCommitmentSummarySelector {
    GiftCommitmentSummaryData fetch(String searchTerm, Id commitmentId);
}