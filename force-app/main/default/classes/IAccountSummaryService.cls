/**
 * Service contract for the Account 360 summary. The Agent Action depends on this
 * interface (not the concrete class) so it can be unit-tested with a mock.
 */
public interface IAccountSummaryService {
    AccountSummaryResult getSummary(String searchTerm, Id accountId);
}