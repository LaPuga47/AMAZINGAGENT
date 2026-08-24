/**
 * Service contract for the Restriction 360. The Agent Action depends on this
 * interface (not the concrete class) so it can be unit-tested with a mock.
 */
public interface IRestrictionSummaryService {
    RestrictionSummaryResult getSummary(String searchTerm, Id restrictionId);
}