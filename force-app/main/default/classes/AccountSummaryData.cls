/**
 * Internal container of the raw records gathered for an Account 360 summary.
 * Populated by the selector, consumed (and computed on) by the service. Not
 * exposed to the agent.
 */
public class AccountSummaryData {
  public Account acct;
  public List<Contact> contacts = new List<Contact>();
  public List<Account> childAccounts = new List<Account>();
  public List<AccountContactRelation> relationships = new List<AccountContactRelation>();
  public List<Opportunity> opportunities = new List<Opportunity>();
  public List<GiftCommitment> commitments = new List<GiftCommitment>();
  public List<GiftTransaction> transactions = new List<GiftTransaction>();
  public List<Restriction__c> restrictions = new List<Restriction__c>();
  public DS360oi__DonorSearch_del_del__c donorSearch;
}