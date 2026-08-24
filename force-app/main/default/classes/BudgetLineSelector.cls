/**
 * BudgetLineSelector — all SOQL for Budget_Line__c. Runs WITH USER_MODE
 * (AccessLevel.USER_MODE) so FLS and sharing are enforced for the running employee.
 * No business logic, no DML.
 *
 * Every query is scoped to the current budget scenario
 * (Budget_Scenario__r.Is_Current_Scenario__c = true), matching how the rest of the
 * A-maize-ing headroom code reads budget data.
 */
public with sharing class BudgetLineSelector implements IBudgetLineSelector {

    // All fields the Headroom service and formatter need, incl. the org's stored/
    // calculated headroom fields (preferred over recomputing) and the composite key.
    private static final String FIELDS =
        'Id, Name, Fiscal_Year__c, Country__c, BusinessUnit__c, Sub__c, Department__c, ' +
        'Cost_Type__c, Cost_Category__c, Budget_Line_Unique_Key__c, CurrencyIsoCode, ' +
        'Budget_Amount__c, Secured_Funding__c, Likely_Funding__c, Pipeline_Funding__c, ' +
        'Forecast_Funding__c, Secured_Headroom__c, Forecast_Headroom__c, Headroom_status__c, Matched__c';

    private static final String CURRENT_SCENARIO = 'Budget_Scenario__r.Is_Current_Scenario__c = true';

    public List<Budget_Line__c> findByUniqueKey(String key) {
        if (String.isBlank(key)) {
            return new List<Budget_Line__c>();
        }
        Map<String, Object> binds = new Map<String, Object>{ 'key' => key };
        String query =
            'SELECT ' + FIELDS + ' FROM Budget_Line__c ' +
            'WHERE ' + CURRENT_SCENARIO + ' AND Budget_Line_Unique_Key__c = :key ' +
            'LIMIT 10';
        return Database.queryWithBinds(query, binds, AccessLevel.USER_MODE);
    }

    public List<Budget_Line__c> findByDimensions(BudgetLineDimensions d) {
        if (d == null) {
            return new List<Budget_Line__c>();
        }
        List<String> clauses = new List<String>{ CURRENT_SCENARIO };
        Map<String, Object> binds = new Map<String, Object>();

        // Only supplied (non-null) dimensions constrain the search. An explicit "N/A"
        // is a real value here and is matched exactly, not skipped.
        if (d.fiscalYear != null)   { clauses.add('Fiscal_Year__c = :fy');       binds.put('fy', d.fiscalYear); }
        if (d.country != null)      { clauses.add('Country__c = :country');       binds.put('country', d.country); }
        if (d.businessUnit != null) { clauses.add('BusinessUnit__c = :bu');       binds.put('bu', d.businessUnit); }
        if (d.subUnit != null)      { clauses.add('Sub__c = :sub');               binds.put('sub', d.subUnit); }
        if (d.department != null)   { clauses.add('Department__c = :dept');       binds.put('dept', d.department); }
        if (d.costType != null)     { clauses.add('Cost_Type__c = :ctype');       binds.put('ctype', d.costType); }
        if (d.costCategory != null) { clauses.add('Cost_Category__c = :ccat');    binds.put('ccat', d.costCategory); }

        binds.put('lim', 200);
        String query =
            'SELECT ' + FIELDS + ' FROM Budget_Line__c ' +
            'WHERE ' + String.join(clauses, ' AND ') + ' ' +
            'ORDER BY Sub__c, Department__c, Cost_Type__c, Cost_Category__c ' +
            'LIMIT :lim';
        return Database.queryWithBinds(query, binds, AccessLevel.USER_MODE);
    }

    public List<Budget_Line__c> findPortfolio(String country, String fiscalYear) {
        List<String> clauses = new List<String>{ CURRENT_SCENARIO };
        Map<String, Object> binds = new Map<String, Object>();
        if (String.isNotBlank(country))    { clauses.add('Country__c = :country'); binds.put('country', country); }
        if (String.isNotBlank(fiscalYear)) { clauses.add('Fiscal_Year__c = :fy');  binds.put('fy', fiscalYear); }
        binds.put('lim', 1000);
        String query =
            'SELECT ' + FIELDS + ' FROM Budget_Line__c ' +
            'WHERE ' + String.join(clauses, ' AND ') + ' ' +
            'LIMIT :lim';
        return Database.queryWithBinds(query, binds, AccessLevel.USER_MODE);
    }
}
