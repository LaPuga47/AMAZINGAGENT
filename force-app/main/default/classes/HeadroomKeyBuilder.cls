/**
 * HeadroomKeyBuilder — builds the Budget Line composite key in Apex, byte-for-byte
 * identical to the org's declarative keys so a key built here always resolves the
 * same Budget Line the platform would.
 *
 * Two org formulas define the format and MUST stay in sync with this class:
 *   - Budget_Line__c.Budget_Line_Unique_Key__c  (built by the
 *     "Budget Line Unique Composite Key" before-save flow)
 *   - Allocation__c.Allocation_Match_Key__c      (formula field, sourced from Restriction__r)
 *
 * Both concatenate, in THIS order, each value wrapped in UPPER(TRIM(TEXT(...))),
 * joined by a single pipe:
 *
 *   Fiscal Year | Country | Business Unit | Sub-Unit | Cost Type | Department | Cost Category
 *
 * (Allocation's first segment is Fund.Name, which One Acre Fund names by fiscal year,
 * so it aligns with Budget Line's Fiscal_Year__c.)
 *
 * Read-only helper: no SOQL, no DML.
 */
public with sharing class HeadroomKeyBuilder {

    /**
     * Build the composite key from a set of dimensions. A null dimension becomes an
     * empty segment (matching TEXT(null) = '' in the org formulas); callers that need
     * an EXACT unique-key match should supply all seven dimensions first.
     */
    public static String build(BudgetLineDimensions d) {
        if (d == null) {
            d = new BudgetLineDimensions();
        }
        return String.join(new List<String>{
            norm(d.fiscalYear),
            norm(d.country),
            norm(d.businessUnit),
            norm(d.subUnit),
            norm(d.costType),
            norm(d.department),
            norm(d.costCategory)
        }, '|');
    }

    /** Mirror UPPER(TRIM(TEXT(x))): trim, upper-case, and treat null as an empty segment. */
    private static String norm(String value) {
        return value == null ? '' : value.trim().toUpperCase();
    }
}
