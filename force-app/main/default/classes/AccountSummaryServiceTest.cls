@isTest
private class AccountSummaryServiceTest {
  private class MockSelector implements IAccountSummarySelector {
    private AccountSummaryData data;
    private MockSelector(AccountSummaryData d) {
      this.data = d;
    }
    public AccountSummaryData fetch(String s, Id i) {
      return data;
    }
  }

  private static Account acct(String payload) {
    return (Account) JSON.deserialize(payload, Account.class);
  }

  private static AccountSummaryResult run(AccountSummaryData d, Id recId) {
    AccountSummaryService svc = new AccountSummaryService();
    svc.selector = new MockSelector(d);
    return svc.getSummary(null, recId);
  }

  @isTest
  static void organizationSummaryClassifiesAndShowsRelated() {
    AccountSummaryData d = new AccountSummaryData();
    d.acct = acct(
      '{"Id":"001000000000001AAA","Name":"MasterCard Foundation","Type":"Private Foundation","Industry":"Nonprofit",' +
        '"RecordType":{"Name":"Organization","DeveloperName":"Organization"},' +
        '"Donor_Segment__c":"North America Institutional","Donor_Type__c":"Institutional","Donor_Status__c":"Ongoing",' +
        '"Account_Guardian__r":{"Name":"Matthew Forti"},"Owner":{"Name":"Jane Owner"},"Website":"https://x.org","Phone":"555",' +
        '"BillingCity":"Toronto","BillingState":"Ontario","BillingCountry":"Canada","CurrencyIsoCode":"USD",' +
        '"Parent":{"Name":"Global Parent"},"Total_Gift_Amount_Donor_Gift_Summary__c":56000000}'
    );
    d.contacts.add(
      (Contact) JSON.deserialize(
        '{"Id":"003000000000001AAA","Name":"Alice Grant","Title":"Program Officer"}',
        Contact.class
      )
    );
    d.relationships.add(
      (AccountContactRelation) JSON.deserialize(
        '{"ContactId":"003000000000001AAA","Contact":{"Name":"Alice Grant"},"Roles":"Board Member","IsDirect":true}',
        AccountContactRelation.class
      )
    );
    d.childAccounts.add(
      (Account) JSON.deserialize(
        '{"Id":"001000000000009AAA","Name":"Regional Chapter"}',
        Account.class
      )
    );
    d.opportunities.add(
      (Opportunity) JSON.deserialize(
        '{"Id":"006000000000001AAA","Name":"Grant 2024","StageName":"Grant Awarded","Amount":100000,"CloseDate":"2024-02-01"}',
        Opportunity.class
      )
    );
    d.commitments.add(
      (GiftCommitment) JSON.deserialize(
        '{"Id":"6gc000000000001AAA","Name":"Pledge","Status":"Active","ExpectedTotalCmtAmount":100000}',
        GiftCommitment.class
      )
    );
    d.transactions.add(
      (GiftTransaction) JSON.deserialize(
        '{"Id":"6tr000000000001AAA","Name":"GT-1","Status":"Paid","CurrentAmount":50000,"TransactionDate":"2024-03-01"}',
        GiftTransaction.class
      )
    );
    d.restrictions.add(
      (Restriction__c) JSON.deserialize(
        '{"Id":"a0L000000000001AAA","Name":"R-1","Restriction_Country__c":"Kenya"}',
        Restriction__c.class
      )
    );

    AccountSummaryResult r = run(d, '001000000000001AAA');

    System.assertEquals('Organization Account', r.accountCategory);
    System.assertEquals('Organization', r.recordTypeDeveloperName);
    System.assertEquals(false, r.isPersonAccount);
    System.assertEquals('Jane Owner', r.ownerName);
    String t = r.resultsText;
    System.assert(
      t.contains('Account Category: Organization Account'),
      'category: ' + t
    );
    System.assert(t.contains('Record Type: Organization'), 'record type');
    System.assert(
      t.contains('Organization Type: Private Foundation'),
      'org type'
    );
    System.assert(t.contains('Key Contacts: 1'), 'key contacts');
    System.assert(t.contains('Alice Grant'), 'contact name');
    System.assert(t.contains('Parent Account: Global Parent'), 'parent');
    System.assert(t.contains('Child Accounts: 1'), 'children');
    System.assert(t.contains('OPPORTUNITIES (1)'), 'opps');
    System.assert(t.contains('GIFT COMMITMENTS (1)'), 'commitments');
    System.assert(t.contains('GIFT TRANSACTION SUMMARY'), 'txn summary');
    System.assert(t.contains('RESTRICTIONS (1)'), 'restrictions');
    System.assert(!t.containsIgnoreCase('http'), 'no url in text');
    System.assert(!t.contains('001000000000001AAA'), 'no raw id in text');
    System.assert(!t.contains('URL_Redacted'), 'no redacted token');
    System.assert(!r.records.isEmpty(), 'related-people cards present');
    System.assertEquals(
      'Contact',
      r.records[0].objectApiName,
      'org related card is a Contact'
    );
  }

  @isTest
  static void personSummaryUsesAffiliationsNotContacts() {
    AccountSummaryData d = new AccountSummaryData();
    d.acct = acct(
      '{"Id":"001000000000010AAA","Name":"Jane Donor","IsPersonAccount":true,' +
        '"RecordType":{"Name":"Person Account","DeveloperName":"PersonAccount"},' +
        '"PersonContactId":"003000000000010AAA","PersonEmail":"jane@x.com","PersonMobilePhone":"555-1",' +
        '"PersonMailingCity":"Seattle","PersonMailingCountry":"USA","Donor_Type__c":"Individual","Donor_Status__c":"Active",' +
        '"Owner":{"Name":"Rep One"},"CurrencyIsoCode":"USD"}'
    );
    d.relationships.add(
      (AccountContactRelation) JSON.deserialize(
        '{"AccountId":"001000000000001AAA","Account":{"Name":"MasterCard Foundation"},"Roles":"Employee","IsDirect":true}',
        AccountContactRelation.class
      )
    );

    AccountSummaryResult r = run(d, '001000000000010AAA');

    System.assertEquals('Person Account', r.accountCategory);
    System.assertEquals(true, r.isPersonAccount);
    String t = r.resultsText;
    System.assert(
      t.contains('Account Category: Person Account'),
      'person category'
    );
    System.assert(t.contains('Email: jane@x.com'), 'email');
    System.assert(t.contains('Affiliations: 1'), 'affiliations');
    System.assert(t.contains('MasterCard Foundation'), 'affiliated org');
    System.assert(
      !t.contains('Key Contacts'),
      'person must not list key contacts'
    );
    System.assert(!r.records.isEmpty(), 'affiliation cards present');
    System.assertEquals(
      'Account',
      r.records[0].objectApiName,
      'person affiliation card is an Account'
    );
  }

  @isTest
  static void householdSummaryShowsMembers() {
    AccountSummaryData d = new AccountSummaryData();
    d.acct = acct(
      '{"Id":"001000000000020AAA","Name":"Smith Household","Type":"Household",' +
        '"RecordType":{"Name":"Organization","DeveloperName":"Organization"},"Owner":{"Name":"Rep Two"},' +
        '"BillingCity":"Austin","BillingCountry":"USA","CurrencyIsoCode":"USD"}'
    );
    d.contacts.add(
      (Contact) JSON.deserialize(
        '{"Id":"003000000000020AAA","Name":"John Smith","Title":"Head"}',
        Contact.class
      )
    );
    d.contacts.add(
      (Contact) JSON.deserialize(
        '{"Id":"003000000000021AAA","Name":"Mary Smith"}',
        Contact.class
      )
    );

    AccountSummaryResult r = run(d, '001000000000020AAA');

    System.assertEquals('Household Account', r.accountCategory);
    String t = r.resultsText;
    System.assert(
      t.contains('Account Category: Household Account'),
      'household category'
    );
    System.assert(t.contains('Household Members: 2'), 'members count: ' + t);
    System.assert(t.contains('John Smith'), 'member name');
  }

  @isTest
  static void missingTypeOrgStillClassifies() {
    AccountSummaryData d = new AccountSummaryData();
    d.acct = acct(
      '{"Id":"001000000000050AAA","Name":"No Type Org","RecordType":{"Name":"Organization","DeveloperName":"Organization"},"CurrencyIsoCode":"USD"}'
    );
    AccountSummaryResult r = run(d, '001000000000050AAA');
    System.assertEquals('Organization Account', r.accountCategory);
    System.assert(
      r.resultsText.contains('Account Category: Organization Account'),
      'category'
    );
  }

  @isTest
  static void moreThanFiveOpportunitiesShowsAndMore() {
    AccountSummaryData d = new AccountSummaryData();
    d.acct = acct(
      '{"Id":"001000000000030AAA","Name":"Big Org","RecordType":{"Name":"Organization","DeveloperName":"Organization"},"CurrencyIsoCode":"USD"}'
    );
    for (Integer i = 0; i < 7; i++) {
      d.opportunities.add(
        (Opportunity) JSON.deserialize(
          '{"Id":"00600000000000' +
            String.valueOf(1000 + i) +
            '","Name":"Opp ' +
            i +
            '","StageName":"Prospecting","Amount":1000}',
          Opportunity.class
        )
      );
    }
    AccountSummaryResult r = run(d, '001000000000030AAA');
    String t = r.resultsText;
    System.assert(t.contains('OPPORTUNITIES (7)'), 'total 7: ' + t);
    System.assert(t.contains('...and 2 additional records.'), 'and more');
  }

  @isTest
  static void noRelatedRecordsRendersCleanly() {
    AccountSummaryData d = new AccountSummaryData();
    d.acct = acct(
      '{"Id":"001000000000040AAA","Name":"Empty Org","RecordType":{"Name":"Organization","DeveloperName":"Organization"},"CurrencyIsoCode":"USD"}'
    );
    AccountSummaryResult r = run(d, '001000000000040AAA');
    System.assertEquals(true, r.found);
    String t = r.resultsText;
    System.assert(t.contains('OPPORTUNITIES (0)'), 'zero opps');
    System.assert(t.contains('None linked.'), 'none linked');
    System.assert(
      !t.contains('RESTRICTIONS'),
      'no restrictions section when none'
    );
  }

  @isTest
  static void donorResearchSectionRendersWhenPresent() {
    AccountSummaryData d = new AccountSummaryData();
    d.acct = acct(
      '{"Id":"001000000000060AAA","Name":"Research Org","RecordType":{"Name":"Organization","DeveloperName":"Organization"},"CurrencyIsoCode":"USD"}'
    );
    d.donorSearch = (DS360oi__DonorSearch_del_del__c) JSON.deserialize(
      '{"DS360oi__DS_Rating__c":"A+","DS360oi__Capacity_Range_Based_on_Wealth__c":"$1M-$5M",' +
        '"DS360oi__Largest_Gift_Found__c":250000,"DS360oi__Largest_Gift_Found_Lower_Range__c":100000,' +
        '"DS360oi__Largest_Gift_Org__c":"Some Charity","DS360oi__Major_Gift_Likelihood__c":85,' +
        '"DS360oi__Engagement_Score__c":72,"DS360oi__Philanthropy_and_Grant_making_Total__c":5000000,' +
        '"DS360oi__Charitable_Gift_count__c":42}',
      DS360oi__DonorSearch_del_del__c.class
    );
    AccountSummaryResult r = run(d, '001000000000060AAA');
    String t = r.resultsText;
    System.assert(
      t.contains('DONOR RESEARCH (DonorSearch)'),
      'donor research heading: ' + t
    );
    System.assert(t.contains('DS Rating: A+'), 'ds rating');
    System.assert(t.contains('Estimated Giving Capacity: $1M-$5M'), 'capacity');
    System.assert(t.contains('Suggested Ask Range:'), 'ask range');
    System.assert(t.contains('Confirmed Charitable Gifts: 42'), 'gift count');
    System.assert(
      t.contains('Largest Gift Recipient: Some Charity'),
      'recipient'
    );
    System.assert(!t.containsIgnoreCase('http'), 'no url');
    System.assert(!t.contains('URL_Redacted'), 'no redacted token');
  }

  @isTest
  static void donorResearchSuppressesZeroAndEmptyLines() {
    AccountSummaryData d = new AccountSummaryData();
    d.acct = acct(
      '{"Id":"001000000000062AAA","Name":"Sparse Research Org","RecordType":{"Name":"Organization","DeveloperName":"Organization"},"CurrencyIsoCode":"USD"}'
    );
    d.donorSearch = (DS360oi__DonorSearch_del_del__c) JSON.deserialize(
      '{"DS360oi__DS_Rating__c":"DS1-4","DS360oi__Capacity_Range_Based_on_Wealth__c":"$0 - $0",' +
        '"DS360oi__Largest_Gift_Found__c":0,"DS360oi__Largest_Gift_Found_Lower_Range__c":0,' +
        '"DS360oi__Major_Gift_Likelihood__c":86,"DS360oi__Planned_Gift_Likelihood__c":0,' +
        '"DS360oi__DS_AI_Score__c":0,"DS360oi__Philanthropy_and_Grant_making_Total__c":0,' +
        '"DS360oi__Charitable_Gift_count__c":0}',
      DS360oi__DonorSearch_del_del__c.class
    );
    AccountSummaryResult r = run(d, '001000000000062AAA');
    String t = r.resultsText;
    System.assert(
      t.contains('DONOR RESEARCH (DonorSearch)'),
      'section still shown for the meaningful values'
    );
    System.assert(t.contains('DS Rating: DS1-4'), 'rating kept');
    System.assert(
      t.contains('Major Gift Likelihood: 86'),
      'non-zero score kept'
    );
    System.assert(
      !t.contains('Estimated Giving Capacity'),
      'zero capacity suppressed'
    );
    System.assert(
      !t.contains('Suggested Ask Range'),
      'zero ask range suppressed'
    );
    System.assert(
      !t.contains('Planned Gift Likelihood'),
      'zero likelihood suppressed'
    );
    System.assert(!t.contains('AI Score'), 'zero AI score suppressed');
    System.assert(
      !t.contains('Confirmed Philanthropy'),
      'zero philanthropy suppressed'
    );
    System.assert(
      !t.contains('Confirmed Charitable Gifts'),
      'zero gift count suppressed'
    );
  }

  @isTest
  static void donorResearchSectionOmittedWhenAllValuesZero() {
    AccountSummaryData d = new AccountSummaryData();
    d.acct = acct(
      '{"Id":"001000000000063AAA","Name":"Empty Research Org","RecordType":{"Name":"Organization","DeveloperName":"Organization"},"CurrencyIsoCode":"USD"}'
    );
    d.donorSearch = (DS360oi__DonorSearch_del_del__c) JSON.deserialize(
      '{"DS360oi__Capacity_Range_Based_on_Wealth__c":"$0 - $0","DS360oi__Major_Gift_Likelihood__c":0,' +
      '"DS360oi__Philanthropy_and_Grant_making_Total__c":0,"DS360oi__Charitable_Gift_count__c":0}',
      DS360oi__DonorSearch_del_del__c.class
    );
    AccountSummaryResult r = run(d, '001000000000063AAA');
    System.assert(
      !r.resultsText.contains('DONOR RESEARCH'),
      'section omitted when nothing meaningful survives suppression'
    );
  }

  @isTest
  static void donorResearchSectionOmittedWhenAbsent() {
    AccountSummaryData d = new AccountSummaryData();
    d.acct = acct(
      '{"Id":"001000000000061AAA","Name":"No Research Org","RecordType":{"Name":"Organization","DeveloperName":"Organization"},"CurrencyIsoCode":"USD"}'
    );
    AccountSummaryResult r = run(d, '001000000000061AAA');
    System.assert(
      !r.resultsText.contains('DONOR RESEARCH'),
      'no donor research section when absent'
    );
  }

  @isTest
  static void notFoundReturnsFalse() {
    AccountSummaryResult r = run(new AccountSummaryData(), null);
    System.assertEquals(false, r.found);
  }
}