/**
 * Service contract for the Restriction domain. The Agent Action depends on this
 * interface (not the concrete class) so it can be unit-tested with a mock.
 */
public interface IRestrictionService {
    List<RestrictionSummary> findRestrictions(String searchTerm, Id giftCommitmentId, Id opportunityId, String country, Integer maxResults);
}