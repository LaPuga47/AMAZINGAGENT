/**
 * Service contract for the Account domain. The Agent Action depends on this
 * interface (not the concrete class) so it can be unit-tested with a mock.
 */
public interface IAccountService {
    List<AccountSummary> findAccounts(String searchTerm, String accountType, Integer maxResults);
}