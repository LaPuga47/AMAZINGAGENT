/**
 * Service contract for the Campaign Performance 360. The Agent Action depends on
 * this interface (not the concrete class) so it can be unit-tested with a mock.
 */
public interface ICampaignSummaryService {
    CampaignSummaryResult getSummary(String searchTerm, Id campaignId);
}