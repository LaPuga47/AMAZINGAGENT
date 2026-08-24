/**
 * Selector contract for Restriction__c. All Restriction SOQL lives behind this so
 * Services can be unit-tested against a mock (no SOQL/DML in service tests).
 */
public interface IRestrictionSelector {
    List<Restriction__c> search(String searchTerm, Id giftCommitmentId, Id opportunityId, String country, Integer maxRecords);
}