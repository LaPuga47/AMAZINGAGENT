/**
 * All SOQL for Campaign. Runs WITH USER_MODE (AccessLevel.USER_MODE) so FLS and
 * sharing are enforced for the running employee. No business logic, no DML.
 */
public with sharing class CampaignSelector implements ICampaignSelector {
    public List<Campaign> search(String searchTerm, String status, Integer maxRecords) {
        Integer recordLimit = SearchUtils.clampLimit(maxRecords);

        List<String> clauses = new List<String>();
        Map<String, Object> binds = new Map<String, Object>();

        if (String.isNotBlank(searchTerm)) {
            clauses.add('Name LIKE :term');
            binds.put('term', SearchUtils.forContains(searchTerm));
        }
        if (String.isNotBlank(status)) {
            clauses.add('Status = :status');
            binds.put('status', status);
        }
        binds.put('recordLimit', recordLimit);

        String whereClause = clauses.isEmpty() ? '' : ' WHERE ' + String.join(clauses, ' AND ');
        String query =
            'SELECT Id, Name, Type, Status, StartDate, EndDate, IsActive, Owner.Name ' +
            'FROM Campaign' + whereClause +
            ' ORDER BY StartDate DESC NULLS LAST, Name ASC LIMIT :recordLimit';

        return Database.queryWithBinds(query, binds, AccessLevel.USER_MODE);
    }
}