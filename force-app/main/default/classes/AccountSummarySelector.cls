/**
 * Cross-object read layer for the Account 360 summary. All SOQL runs
 * WITH USER_MODE / AccessLevel.USER_MODE (FLS + sharing enforced). No business
 * logic, no DML. Gift Commitments and Gift Transactions are matched by
 * DonorId = the Account; Campaigns are derived in the service from Opportunities.
 * Classification (RecordType, IsPersonAccount, Type) and relationship records
 * (child accounts, AccountContactRelation) are gathered here so the service can
 * classify and adapt deterministically.
 */
public with sharing class AccountSummarySelector implements IAccountSummarySelector {
  private static final String ACCT_FIELDS =
    'Id, Name, Type, Industry, RecordTypeId, RecordType.Name, RecordType.DeveloperName, IsPersonAccount, ' +
    'ParentId, Parent.Name, Phone, Website, ' +
    'PersonContactId, PersonContact.Name, PersonEmail, PersonHomePhone, PersonMobilePhone, ' +
    'PersonMailingCity, PersonMailingState, PersonMailingCountry, ' +
    'Donor_Segment__c, Donor_Type__c, Account_Guardian__r.Name, Rating, Priority__c, Donor_Status__c, ' +
    'BillingStreet, BillingCity, BillingState, BillingPostalCode, BillingCountry, CurrencyIsoCode, Owner.Name, ' +
    'Total_Gift_Amount_Donor_Gift_Summary__c, Gifts_this_Year_Donor_Gift_Summary__c, ' +
    'Last_Gift_Amount_Donor_Gift_Summary__c, Last_Gift_Date_Donor_Gift_Summary__c, Highest_Gift_Amount__c';

  public AccountSummaryData fetch(String searchTerm, Id accountId) {
    AccountSummaryData data = new AccountSummaryData();
    data.acct = findAccount(searchTerm, accountId);
    if (data.acct == null) {
      return data;
    }
    Id aid = data.acct.Id;

    data.contacts = [
      SELECT Id, Name, Title
      FROM Contact
      WHERE AccountId = :aid
      WITH USER_MODE
      ORDER BY Name
      LIMIT 25
    ];
    data.childAccounts = [
      SELECT Id, Name, Type
      FROM Account
      WHERE ParentId = :aid
      WITH USER_MODE
      ORDER BY Name
      LIMIT 25
    ];
    // Affiliations / contact roles. For a Person Account these are the
    // person's affiliations (by their Contact); for org/household they are
    // the account's related contacts.
    if (
      data.acct.IsPersonAccount == true &&
      data.acct.PersonContactId != null
    ) {
      Id personContactId = data.acct.PersonContactId;
      data.relationships = [
        SELECT
          Id,
          AccountId,
          Account.Name,
          ContactId,
          Contact.Name,
          Roles,
          IsDirect,
          IsActive
        FROM AccountContactRelation
        WHERE ContactId = :personContactId
        WITH USER_MODE
        ORDER BY IsDirect DESC
        LIMIT 50
      ];
    } else {
      data.relationships = [
        SELECT
          Id,
          AccountId,
          Account.Name,
          ContactId,
          Contact.Name,
          Roles,
          IsDirect,
          IsActive
        FROM AccountContactRelation
        WHERE AccountId = :aid
        WITH USER_MODE
        ORDER BY IsDirect DESC
        LIMIT 50
      ];
    }
    data.opportunities = [
      SELECT
        Id,
        Name,
        StageName,
        Amount,
        CloseDate,
        Owner.Name,
        CampaignId,
        Campaign.Name,
        Campaign.Status
      FROM Opportunity
      WHERE AccountId = :aid
      WITH USER_MODE
      ORDER BY CloseDate DESC NULLS LAST
      LIMIT 50
    ];
    data.commitments = [
      SELECT
        Id,
        Name,
        Status,
        ExpectedTotalCmtAmount,
        EffectiveStartDate,
        ExpectedEndDate
      FROM GiftCommitment
      WHERE DonorId = :aid
      WITH USER_MODE
      ORDER BY EffectiveStartDate DESC NULLS LAST
      LIMIT 200
    ];
    data.transactions = [
      SELECT Id, Name, Status, CurrentAmount, TransactionDate
      FROM GiftTransaction
      WHERE DonorId = :aid
      WITH USER_MODE
      ORDER BY TransactionDate DESC NULLS LAST
      LIMIT 2000
    ];
    Set<Id> commitmentIds = new Map<Id, GiftCommitment>(data.commitments)
      .keySet();
    data.restrictions = commitmentIds.isEmpty()
      ? new List<Restriction__c>()
      : [
          SELECT Id, Name, Restriction_Country__c
          FROM Restriction__c
          WHERE Gift_Commitment__c IN :commitmentIds
          WITH USER_MODE
          ORDER BY Name
          LIMIT 200
        ];
    data.donorSearch = fetchDonorSearch(data.acct);
    return data;
  }

  /**
   * Most-recent DonorSearch (managed-package) wealth/philanthropy record for the
   * account (or, for a Person Account, matched via its Contact). Guarded by
   * isAccessible() so it silently returns null for users/orgs without access and
   * never breaks the summary.
   */
  private DS360oi__DonorSearch_del_del__c fetchDonorSearch(Account a) {
    if (!Schema.sObjectType.DS360oi__DonorSearch_del_del__c.isAccessible()) {
      return null;
    }
    Id aid = a.Id;
    Id personContactId = a.PersonContactId;
    List<DS360oi__DonorSearch_del_del__c> ds;
    if (a.IsPersonAccount == true && personContactId != null) {
      ds = [
        SELECT
          Id,
          DS360oi__DS_Rating__c,
          DS360oi__Capacity_Range_Based_on_Wealth__c,
          DS360oi__Largest_Gift_Found__c,
          DS360oi__Largest_Gift_Found_Lower_Range__c,
          DS360oi__Largest_Gift_Org__c,
          DS360oi__Major_Gift_Likelihood__c,
          DS360oi__Planned_Gift_Likelihood__c,
          DS360oi__Annual_Fund_Likelihood__c,
          DS360oi__Engagement_Score__c,
          DS360oi__DS_AI_Score__c,
          DS360oi__DonorSearch_Aristotle_Score__c,
          DS360oi__Philanthropy_and_Grant_making_Total__c,
          DS360oi__Charitable_Gift_count__c,
          CurrencyIsoCode
        FROM DS360oi__DonorSearch_del_del__c
        WHERE DS360oi__ID__c = :personContactId OR DS360oi__Account__c = :aid
        WITH USER_MODE
        ORDER BY LastModifiedDate DESC
        LIMIT 1
      ];
    } else {
      ds = [
        SELECT
          Id,
          DS360oi__DS_Rating__c,
          DS360oi__Capacity_Range_Based_on_Wealth__c,
          DS360oi__Largest_Gift_Found__c,
          DS360oi__Largest_Gift_Found_Lower_Range__c,
          DS360oi__Largest_Gift_Org__c,
          DS360oi__Major_Gift_Likelihood__c,
          DS360oi__Planned_Gift_Likelihood__c,
          DS360oi__Annual_Fund_Likelihood__c,
          DS360oi__Engagement_Score__c,
          DS360oi__DS_AI_Score__c,
          DS360oi__DonorSearch_Aristotle_Score__c,
          DS360oi__Philanthropy_and_Grant_making_Total__c,
          DS360oi__Charitable_Gift_count__c,
          CurrencyIsoCode
        FROM DS360oi__DonorSearch_del_del__c
        WHERE DS360oi__Account__c = :aid
        WITH USER_MODE
        ORDER BY LastModifiedDate DESC
        LIMIT 1
      ];
    }
    return ds.isEmpty() ? null : ds[0];
  }

  private Account findAccount(String searchTerm, Id accountId) {
    if (accountId != null) {
      List<Account> byId = Database.queryWithBinds(
        'SELECT ' + ACCT_FIELDS + ' FROM Account WHERE Id = :accountId LIMIT 1',
        new Map<String, Object>{ 'accountId' => accountId },
        AccessLevel.USER_MODE
      );
      return byId.isEmpty() ? null : byId[0];
    }
    if (String.isBlank(searchTerm)) {
      return null;
    }
    String likeTerm = SearchUtils.forContains(searchTerm);
    List<Account> matches = Database.queryWithBinds(
      'SELECT ' +
        ACCT_FIELDS +
        ' FROM Account WHERE Name LIKE :likeTerm ORDER BY Name LIMIT 10',
      new Map<String, Object>{ 'likeTerm' => likeTerm },
      AccessLevel.USER_MODE
    );
    if (matches.isEmpty()) {
      return null;
    }
    Account best = matches[0];
    Integer bestScore = -1;
    for (Account a : matches) {
      Integer score = EntityMatcher.score(searchTerm, a.Name);
      if (score > bestScore) {
        bestScore = score;
        best = a;
      }
    }
    return best;
  }
}