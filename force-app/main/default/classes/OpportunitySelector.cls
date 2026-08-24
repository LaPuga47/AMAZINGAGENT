/**
 * All SOQL for Opportunity. Runs WITH USER_MODE (AccessLevel.USER_MODE) so FLS
 * and sharing are enforced for the running employee. No business logic, no DML.
 */
public with sharing class OpportunitySelector implements IOpportunitySelector {
    public List<Opportunity> search(String searchTerm, Id accountId, String stage, Integer maxRecords) {
        Integer recordLimit = SearchUtils.clampLimit(maxRecords);

        List<String> clauses = new List<String>();
        Map<String, Object> binds = new Map<String, Object>();

        if (String.isNotBlank(searchTerm)) {
            clauses.add('Name LIKE :term');
            binds.put('term', SearchUtils.forContains(searchTerm));
        }
        if (accountId != null) {
            clauses.add('AccountId = :accountId');
            binds.put('accountId', accountId);
        }
        if (String.isNotBlank(stage)) {
            clauses.add('StageName = :stage');
            binds.put('stage', stage);
        }
        binds.put('recordLimit', recordLimit);

        String whereClause = clauses.isEmpty() ? '' : ' WHERE ' + String.join(clauses, ' AND ');
        String query =
            'SELECT Id, Name, StageName, Amount, CloseDate, Account.Name, Owner.Name ' +
            'FROM Opportunity' + whereClause +
            ' ORDER BY CloseDate DESC NULLS LAST, Name ASC LIMIT :recordLimit';

        return Database.queryWithBinds(query, binds, AccessLevel.USER_MODE);
    }
}