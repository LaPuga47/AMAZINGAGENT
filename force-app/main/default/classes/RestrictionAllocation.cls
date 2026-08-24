/**
 * Reusable, deterministic restriction-allocation math (v2 finance rules), shared
 * by the Restriction, Gift Commitment, and Opportunity 360 summaries.
 *
 * Business rules (confirmed defaults; subject to Grants Finance review):
 *  - Total Allocated for a restriction = sum of its yearly x20YY_Funds_Allocated__c
 *    fields (2021–2040).
 *  - Unallocated = (commitment) Expected Total − Total Restriction Allocated.
 *  - Status = In sync (difference ~0) / Under-allocated (unallocated remains) /
 *    Over-allocated (allocations exceed expected).
 *
 * Callers must query the yearly fields (see yearlyFields()) on the Restriction__c
 * records they pass in.
 */
public inherited sharing class RestrictionAllocation {
    public static final Integer FIRST_YEAR = 2021;
    public static final Integer LAST_YEAR = 2040;
    private static final Decimal TOLERANCE = 0.01;

    /** SOQL field names for the yearly allocation fields, for dynamic queries. */
    public static List<String> yearlyFields() {
        List<String> fields = new List<String>();
        for (Integer y = FIRST_YEAR; y <= LAST_YEAR; y++) {
            fields.add('x' + y + '_Funds_Allocated__c');
        }
        return fields;
    }

    /** Sum of populated, non-zero yearly fields for one restriction (null if none). */
    public static Decimal totalAllocated(Restriction__c restriction) {
        Decimal total = null;
        for (Integer y = FIRST_YEAR; y <= LAST_YEAR; y++) {
            Object value = restriction.get('x' + y + '_Funds_Allocated__c');
            if (value != null) {
                Decimal amt = (Decimal) value;
                if (amt != 0) {
                    total = (total == null ? 0 : total) + amt;
                }
            }
        }
        return total;
    }

    /** Combined total allocated across a set of restrictions (null if none). */
    public static Decimal totalAllocated(List<Restriction__c> restrictions) {
        Decimal total = null;
        if (restrictions != null) {
            for (Restriction__c r : restrictions) {
                Decimal t = totalAllocated(r);
                if (t != null) {
                    total = (total == null ? 0 : total) + t;
                }
            }
        }
        return total;
    }

    /** Reconciles an expected total against a set of restriction allocations. */
    public static Reconciliation reconcile(Decimal expected, List<Restriction__c> restrictions) {
        Reconciliation result = new Reconciliation();
        result.expected = expected;
        result.allocated = totalAllocated(restrictions);
        Decimal alloc = result.allocated == null ? 0 : result.allocated;

        if (restrictions == null || restrictions.isEmpty()) {
            result.unallocated = expected;
            result.status = 'No restrictions linked (funds are unrestricted or not yet allocated).';
            return result;
        }
        if (expected == null) {
            result.status = 'Cannot evaluate — no expected total available.';
            return result;
        }

        result.unallocated = expected - alloc;
        if (result.unallocated.abs() < TOLERANCE) {
            result.status = 'In sync — restrictions fully allocate the expected total.';
        } else if (result.unallocated > 0) {
            result.status = 'Under-allocated — unallocated funds remain.';
        } else {
            result.status = 'Over-allocated — restriction allocations exceed the expected total.';
        }
        return result;
    }

    /** Result of a reconciliation. Amounts are raw; callers format with currency. */
    public class Reconciliation {
        public Decimal expected;
        public Decimal allocated;
        public Decimal unallocated;
        public String status;
    }
}