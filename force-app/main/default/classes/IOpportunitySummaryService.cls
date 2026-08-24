/**
 * Service contract for the Opportunity 360 summary. The Agent Action depends on
 * this interface (not the concrete class) so it can be unit-tested with a mock.
 */
public interface IOpportunitySummaryService {
    OpportunitySummaryResult getSummary(String searchTerm, Id opportunityId);
}