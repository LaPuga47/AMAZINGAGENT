/**
 * Service contract for the Opportunity domain. The Agent Action depends on this
 * interface (not the concrete class) so it can be unit-tested with a mock.
 */
public interface IOpportunityService {
    List<OpportunitySummary> findOpportunities(String searchTerm, Id accountId, String stage, Integer maxResults);
}