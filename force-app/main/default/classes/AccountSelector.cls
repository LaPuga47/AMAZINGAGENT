/**
 * All SOQL for Account. Runs WITH USER_MODE (AccessLevel.USER_MODE) so FLS and
 * sharing are enforced for the running employee. No business logic, no DML.
 */
public with sharing class AccountSelector implements IAccountSelector {
    public List<Account> search(String searchTerm, String accountType, Integer maxRecords) {
        Integer recordLimit = SearchUtils.clampLimit(maxRecords);

        List<String> clauses = new List<String>();
        Map<String, Object> binds = new Map<String, Object>();

        if (String.isNotBlank(searchTerm)) {
            clauses.add('Name LIKE :term');
            binds.put('term', SearchUtils.forContains(searchTerm));
        }
        if (String.isNotBlank(accountType)) {
            clauses.add('Type = :accountType');
            binds.put('accountType', accountType);
        }
        binds.put('recordLimit', recordLimit);

        String whereClause = clauses.isEmpty() ? '' : ' WHERE ' + String.join(clauses, ' AND ');
        String query =
            'SELECT Id, Name, Type, Industry, Phone, Website, BillingCity, BillingCountry, Owner.Name ' +
            'FROM Account' + whereClause +
            ' ORDER BY Name ASC LIMIT :recordLimit';

        return Database.queryWithBinds(query, binds, AccessLevel.USER_MODE);
    }
}