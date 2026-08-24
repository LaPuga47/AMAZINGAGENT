/**
 * Service contract for the Campaign domain. The Agent Action depends on this
 * interface (not the concrete class) so it can be unit-tested with a mock.
 */
public interface ICampaignService {
    List<CampaignSummary> findCampaigns(String searchTerm, String status, Integer maxResults);
}