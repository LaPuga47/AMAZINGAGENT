/**
 * AllocationSelector — all SOQL for Allocation__c. Runs WITH USER_MODE
 * (AccessLevel.USER_MODE) so FLS and sharing are enforced for the running employee.
 * No business logic, no DML.
 *
 * Two lookups mirror the project's approved Allocation-to-Budget-Line relationship,
 * in priority order:
 *   1. byBudgetLineId — the DIRECT Budget_Line__c lookup (populated by the
 *      "Allocation - Budget Line Linking" flow when the match key resolves).
 *   2. byMatchKeyUnlinked — the approved Match Key (Allocation_Match_Key__c equals
 *      Budget_Line__c.Budget_Line_Unique_Key__c), for allocations not yet linked.
 * This class does NOT invent a new matching algorithm; it reuses the org's keys.
 */
public with sharing class AllocationSelector implements IAllocationSelector {

    private static final String FIELDS =
        'Id, Name, Budget_Line__c, Allocation_Type__c, Allocation_Status__c, ' +
        'Funds_Allocated__c, Allocation_Match_Key__c, CurrencyIsoCode, ' +
        'Restriction__r.Gift_Commitment__r.Opportunity.Name, ' +
        'Restriction__r.Gift_Commitment__r.Opportunity.Amount, ' +
        'Restriction__r.Gift_Commitment__r.Opportunity.StageName';

    public List<Allocation__c> byBudgetLineId(Id budgetLineId) {
        if (budgetLineId == null) {
            return new List<Allocation__c>();
        }
        Map<String, Object> binds = new Map<String, Object>{ 'blid' => budgetLineId, 'lim' => 1000 };
        String query =
            'SELECT ' + FIELDS + ' FROM Allocation__c ' +
            'WHERE Budget_Line__c = :blid ' +
            'LIMIT :lim';
        return Database.queryWithBinds(query, binds, AccessLevel.USER_MODE);
    }

    public List<Allocation__c> byMatchKeyUnlinked(String matchKey) {
        if (String.isBlank(matchKey)) {
            return new List<Allocation__c>();
        }
        Map<String, Object> binds = new Map<String, Object>{ 'key' => matchKey, 'lim' => 1000 };
        String query =
            'SELECT ' + FIELDS + ' FROM Allocation__c ' +
            'WHERE Allocation_Match_Key__c = :key AND Budget_Line__c = null ' +
            'LIMIT :lim';
        return Database.queryWithBinds(query, binds, AccessLevel.USER_MODE);
    }
}
