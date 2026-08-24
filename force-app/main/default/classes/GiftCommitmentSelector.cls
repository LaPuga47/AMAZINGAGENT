/**
 * All SOQL for GiftCommitment. Runs WITH USER_MODE (AccessLevel.USER_MODE) so FLS
 * and sharing are enforced for the running employee. No business logic, no DML.
 */
public with sharing class GiftCommitmentSelector implements IGiftCommitmentSelector {
    public List<GiftCommitment> search(String searchTerm, Id donorId, String status, Integer maxRecords) {
        Integer recordLimit = SearchUtils.clampLimit(maxRecords);

        List<String> clauses = new List<String>();
        Map<String, Object> binds = new Map<String, Object>();

        if (String.isNotBlank(searchTerm)) {
            clauses.add('Name LIKE :term');
            binds.put('term', SearchUtils.forContains(searchTerm));
        }
        if (donorId != null) {
            clauses.add('DonorId = :donorId');
            binds.put('donorId', donorId);
        }
        if (String.isNotBlank(status)) {
            clauses.add('Status = :status');
            binds.put('status', status);
        }
        binds.put('recordLimit', recordLimit);

        String whereClause = clauses.isEmpty() ? '' : ' WHERE ' + String.join(clauses, ' AND ');
        String query =
            'SELECT Id, Name, Status, DonorId, Donor.Name, ExpectedTotalCmtAmount, ' +
            'TotalPaidTransactionAmount, Remaining_Balance__c, NextTransactionDate, ' +
            'NextTransactionAmount, EffectiveStartDate, ExpectedEndDate, Owner.Name ' +
            'FROM GiftCommitment' + whereClause +
            ' ORDER BY EffectiveStartDate DESC NULLS LAST, Name ASC LIMIT :recordLimit';

        return Database.queryWithBinds(query, binds, AccessLevel.USER_MODE);
    }
}