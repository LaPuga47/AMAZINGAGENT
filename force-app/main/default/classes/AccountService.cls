/**
 * Account business logic: delegates querying to the Selector, maps records to
 * FLS-safe AccountSummary DTOs, and ranks by relevance when a search term is
 * supplied. No SOQL/DML here. The selector is injectable for unit testing.
 */
public with sharing class AccountService implements IAccountService {
  @TestVisible
  private IAccountSelector selector = new AccountSelector();

  public List<AccountSummary> findAccounts(
    String searchTerm,
    String accountType,
    Integer maxResults
  ) {
    List<Account> records = selector.search(
      searchTerm,
      accountType,
      maxResults
    );

    List<AccountSummary> summaries = new List<AccountSummary>();
    for (Account acct : records) {
      summaries.add(toSummary(acct));
    }

    if (String.isNotBlank(searchTerm)) {
      summaries = sortByRelevance(searchTerm, summaries);
    }
    return summaries;
  }

  private AccountSummary toSummary(Account acct) {
    AccountSummary summary = new AccountSummary();
    summary.id = acct.Id;
    summary.name = acct.Name;
    summary.type = acct.Type;
    summary.industry = acct.Industry;
    summary.phone = acct.Phone;
    summary.website = acct.Website;
    summary.city = acct.BillingCity;
    summary.country = acct.BillingCountry;
    summary.ownerName = acct.Owner == null ? null : acct.Owner.Name;
    summary.record = new AgentRecordResult(acct.Id, 'Account', acct.Name).withSubtitle(acct.Type).withSummary(acct.BillingCountry);
    return summary;
  }

  private List<AccountSummary> sortByRelevance(
    String term,
    List<AccountSummary> items
  ) {
    List<RankedSummary> ranked = new List<RankedSummary>();
    for (AccountSummary item : items) {
      ranked.add(new RankedSummary(EntityMatcher.score(term, item.name), item));
    }
    ranked.sort();
    List<AccountSummary> ordered = new List<AccountSummary>();
    for (RankedSummary entry : ranked) {
      ordered.add(entry.summary);
    }
    return ordered;
  }

  /** Sorts by relevance score descending. */
  private class RankedSummary implements Comparable {
    private final Integer score;
    private final AccountSummary summary;

    private RankedSummary(Integer score, AccountSummary summary) {
      this.score = score;
      this.summary = summary;
    }

    public Integer compareTo(Object other) {
      return ((RankedSummary) other).score - this.score;
    }
  }
}