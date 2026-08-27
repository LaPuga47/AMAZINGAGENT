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
        'Funds_Allocated__c, Prob_Weighted_Allocation_Amount__c, Allocation_Match_Key__c, CurrencyIsoCode, ' +
        'Restriction__c, Restriction__r.Name, ' +
        'Restriction__r.Restriction_Country__c, Restriction__r.Business_Unit__c, ' +
        'Restriction__r.Gift_Commitment__c, Restriction__r.Gift_Commitment__r.Name, ' +
        'Restriction__r.Gift_Commitment__r.Opportunity.Id, ' +
        'Restriction__r.Gift_Commitment__r.Opportunity.Name, ' +
        'Restriction__r.Gift_Commitment__r.Opportunity.Amount, ' +
        'Restriction__r.Gift_Commitment__r.Opportunity.Probability, ' +
        'Restriction__r.Gift_Commitment__r.Opportunity.StageName, ' +
        'Restriction__r.Gift_Commitment__r.Opportunity.CloseDate, ' +
        'Restriction__r.Gift_Commitment__r.Opportunity.Guardian__c, ' +
        'Restriction__r.Gift_Commitment__r.Opportunity.AccountId, ' +
        'Restriction__r.Gift_Commitment__r.Opportunity.Account.Name';

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

    /**
     * Portfolio rollup: competing (Likely + Pipeline, non-cancelled) allocation exposure
     * summed and grouped by the linked Budget Line's (Country, Business Unit, Department,
     * Fiscal Year), across the current scenario. One query for the whole portfolio.
     */
    public List<AggregateResult> aggregateCompetingPortfolio(String country, String fiscalYear) {
        List<String> clauses = new List<String>{
            'Budget_Line__r.Budget_Scenario__r.Is_Current_Scenario__c = true',
            'Allocation_Type__c IN (\'Likely\',\'Pipeline\')',
            'Allocation_Status__c != \'Cancelled\''
        };
        Map<String, Object> binds = new Map<String, Object>();
        if (String.isNotBlank(country))    { clauses.add('Budget_Line__r.Country__c = :country'); binds.put('country', country); }
        if (String.isNotBlank(fiscalYear)) { clauses.add('Budget_Line__r.Fiscal_Year__c = :fy');  binds.put('fy', fiscalYear); }
        String query =
            'SELECT Budget_Line__r.Country__c c, Budget_Line__r.BusinessUnit__c bu, ' +
            'Budget_Line__r.Department__c dept, Budget_Line__r.Fiscal_Year__c fy, ' +
            'SUM(Funds_Allocated__c) amt, COUNT(Id) cnt ' +
            'FROM Allocation__c WHERE ' + String.join(clauses, ' AND ') +
            ' GROUP BY Budget_Line__r.Country__c, Budget_Line__r.BusinessUnit__c, ' +
            'Budget_Line__r.Department__c, Budget_Line__r.Fiscal_Year__c LIMIT 5000';
        return Database.queryWithBinds(query, binds, AccessLevel.USER_MODE);
    }

    /** Allocations DIRECTLY linked to any of the given Budget Lines (scope may span lines). */
    public List<Allocation__c> byBudgetLineIds(Set<Id> budgetLineIds) {
        if (budgetLineIds == null || budgetLineIds.isEmpty()) {
            return new List<Allocation__c>();
        }
        Map<String, Object> binds = new Map<String, Object>{ 'ids' => budgetLineIds, 'lim' => 2000 };
        String query =
            'SELECT ' + FIELDS + ' FROM Allocation__c ' +
            'WHERE Budget_Line__c IN :ids ' +
            'LIMIT :lim';
        return Database.queryWithBinds(query, binds, AccessLevel.USER_MODE);
    }

    /**
     * Allocations for a given Opportunity, reached through the only path that exists in this
     * org: Allocation -> Restriction -> Gift Commitment -> Opportunity (there is no direct
     * Opportunity lookup on Allocation__c). Used to navigate from an Opportunity to the
     * Budget Lines its funding is allocated against.
     */
    public List<Allocation__c> byOpportunityId(Id opportunityId) {
        if (opportunityId == null) {
            return new List<Allocation__c>();
        }
        Map<String, Object> binds = new Map<String, Object>{ 'oid' => opportunityId, 'lim' => 2000 };
        String query =
            'SELECT ' + FIELDS + ' FROM Allocation__c ' +
            'WHERE Restriction__r.Gift_Commitment__r.OpportunityId = :oid ' +
            'LIMIT :lim';
        return Database.queryWithBinds(query, binds, AccessLevel.USER_MODE);
    }

    /**
     * ALL allocations for a set of Opportunities (any Budget Line / scope), for computing
     * each opportunity's total mapped allocation vs. its scope exposure. One bulk query.
     */
    public List<Allocation__c> byOpportunityIds(Set<Id> opportunityIds) {
        if (opportunityIds == null || opportunityIds.isEmpty()) {
            return new List<Allocation__c>();
        }
        Map<String, Object> binds = new Map<String, Object>{ 'oids' => opportunityIds, 'lim' => 5000 };
        String query =
            'SELECT ' + FIELDS + ' FROM Allocation__c ' +
            'WHERE Restriction__r.Gift_Commitment__r.OpportunityId IN :oids ' +
            'LIMIT :lim';
        return Database.queryWithBinds(query, binds, AccessLevel.USER_MODE);
    }

    /** Not-yet-linked allocations whose Match Key equals any of the given Budget Line keys. */
    public List<Allocation__c> byMatchKeysUnlinked(Set<String> matchKeys) {
        if (matchKeys == null || matchKeys.isEmpty()) {
            return new List<Allocation__c>();
        }
        Map<String, Object> binds = new Map<String, Object>{ 'keys' => matchKeys, 'lim' => 2000 };
        String query =
            'SELECT ' + FIELDS + ' FROM Allocation__c ' +
            'WHERE Allocation_Match_Key__c IN :keys AND Budget_Line__c = null ' +
            'LIMIT :lim';
        return Database.queryWithBinds(query, binds, AccessLevel.USER_MODE);
    }
}
