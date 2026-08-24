/**
 * All SOQL for Restriction__c. Runs WITH USER_MODE (AccessLevel.USER_MODE) so FLS
 * and sharing are enforced for the running employee. No business logic, no DML.
 */
public with sharing class RestrictionSelector implements IRestrictionSelector {
    public List<Restriction__c> search(String searchTerm, Id giftCommitmentId, Id opportunityId, String country, Integer maxRecords) {
        Integer recordLimit = SearchUtils.clampLimit(maxRecords);

        List<String> clauses = new List<String>();
        Map<String, Object> binds = new Map<String, Object>();

        if (String.isNotBlank(searchTerm)) {
            clauses.add('Name LIKE :term');
            binds.put('term', SearchUtils.forContains(searchTerm));
        }
        if (giftCommitmentId != null) {
            clauses.add('Gift_Commitment__c = :giftCommitmentId');
            binds.put('giftCommitmentId', giftCommitmentId);
        }
        if (opportunityId != null) {
            clauses.add('Gift_Commitment__r.OpportunityId = :opportunityId');
            binds.put('opportunityId', opportunityId);
        }
        if (String.isNotBlank(country)) {
            clauses.add('Restriction_Country__c = :country');
            binds.put('country', country);
        }
        binds.put('recordLimit', recordLimit);

        String whereClause = clauses.isEmpty() ? '' : ' WHERE ' + String.join(clauses, ' AND ');
        String query =
            'SELECT Id, Name, Gift_Commitment__c, Gift_Commitment__r.Name, Restriction_Country__c, ' +
            'Staff_or_Overhead__c, Is_this_grant_time_restricted__c, Theme__c, Time_Allocation__c, ' +
            'Additional_Restriction_Notes__c ' +
            'FROM Restriction__c' + whereClause +
            ' ORDER BY Name ASC LIMIT :recordLimit';

        return Database.queryWithBinds(query, binds, AccessLevel.USER_MODE);
    }
}