/**
 * Read layer for the Restriction 360. Queries the Restriction__c with its parent
 * Gift Commitment (and donor) context plus the yearly Funds Allocated fields
 * (built dynamically). Runs in USER_MODE. No business logic, no DML.
 */
public with sharing class RestrictionSummarySelector implements IRestrictionSummarySelector {
    public static final Integer FIRST_YEAR = 2021;
    public static final Integer LAST_YEAR = 2040;

    public Restriction__c fetch(String searchTerm, Id restrictionId) {
        String fields = baseFields();
        Map<String, Object> binds = new Map<String, Object>();

        if (restrictionId != null) {
            binds.put('rid', restrictionId);
            String q = 'SELECT ' + fields + ' FROM Restriction__c WHERE Id = :rid LIMIT 1';
            List<Restriction__c> byId = Database.queryWithBinds(q, binds, AccessLevel.USER_MODE);
            return byId.isEmpty() ? null : byId[0];
        }
        if (String.isBlank(searchTerm)) {
            return null;
        }
        binds.put('term', SearchUtils.forContains(searchTerm));
        String q = 'SELECT ' + fields + ' FROM Restriction__c WHERE Name LIKE :term ORDER BY Name LIMIT 10';
        List<Restriction__c> matches = Database.queryWithBinds(q, binds, AccessLevel.USER_MODE);
        if (matches.isEmpty()) {
            return null;
        }
        Restriction__c best = matches[0];
        Integer bestScore = -1;
        for (Restriction__c r : matches) {
            Integer score = EntityMatcher.score(searchTerm, r.Name);
            if (score > bestScore) {
                bestScore = score;
                best = r;
            }
        }
        return best;
    }

    private String baseFields() {
        List<String> f = new List<String>{
            'Id', 'Name', 'Gift_Commitment__c', 'Gift_Commitment__r.Name', 'Gift_Commitment__r.Donor.Name',
            'Restriction_Country__c', 'Staff_or_Overhead__c', 'Is_this_grant_time_restricted__c', 'Theme__c',
            'Time_Allocation__c', 'Additional_Restriction_Notes__c', 'Is_this_a_grant_to_a_sub_grantee__c',
            'Sub_grantee_Name__c', 'CurrencyIsoCode'
        };
        for (Integer y = FIRST_YEAR; y <= LAST_YEAR; y++) {
            f.add('x' + y + '_Funds_Allocated__c');
        }
        return String.join(f, ', ');
    }
}