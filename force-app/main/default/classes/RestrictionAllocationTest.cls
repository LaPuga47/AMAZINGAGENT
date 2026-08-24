@isTest
private class RestrictionAllocationTest {
    private static Restriction__c withYears(Decimal y2025, Decimal y2026) {
        Map<String, Object> m = new Map<String, Object>{ 'attributes' => new Map<String, Object>{ 'type' => 'Restriction__c' } };
        if (y2025 != null) {
            m.put('x2025_Funds_Allocated__c', y2025);
        }
        if (y2026 != null) {
            m.put('x2026_Funds_Allocated__c', y2026);
        }
        return (Restriction__c) JSON.deserialize(JSON.serialize(m), Restriction__c.class);
    }

    @isTest
    static void yearlyFieldsCoverFullRange() {
        List<String> fields = RestrictionAllocation.yearlyFields();
        System.assertEquals(20, fields.size(), '2021..2040 inclusive');
        System.assert(fields.contains('x2021_Funds_Allocated__c'));
        System.assert(fields.contains('x2040_Funds_Allocated__c'));
    }

    @isTest
    static void totalAllocatedSumsYears() {
        System.assertEquals(250000, RestrictionAllocation.totalAllocated(withYears(100000, 150000)));
        System.assertEquals(null, RestrictionAllocation.totalAllocated(withYears(null, null)), 'no years -> null');
        System.assertEquals(250000, RestrictionAllocation.totalAllocated(
            new List<Restriction__c>{ withYears(100000, null), withYears(null, 150000) }
        ));
    }

    @isTest
    static void reconcileInSync() {
        RestrictionAllocation.Reconciliation r = RestrictionAllocation.reconcile(
            250000, new List<Restriction__c>{ withYears(100000, 150000) }
        );
        System.assertEquals(250000, r.allocated);
        System.assertEquals(0, r.unallocated);
        System.assert(r.status.startsWith('In sync'), r.status);
    }

    @isTest
    static void reconcileUnderAllocated() {
        RestrictionAllocation.Reconciliation r = RestrictionAllocation.reconcile(
            300000, new List<Restriction__c>{ withYears(100000, 150000) }
        );
        System.assertEquals(50000, r.unallocated);
        System.assert(r.status.startsWith('Under-allocated'), r.status);
    }

    @isTest
    static void reconcileOverAllocated() {
        RestrictionAllocation.Reconciliation r = RestrictionAllocation.reconcile(
            200000, new List<Restriction__c>{ withYears(100000, 150000) }
        );
        System.assertEquals(-50000, r.unallocated);
        System.assert(r.status.startsWith('Over-allocated'), r.status);
    }

    @isTest
    static void reconcileNoRestrictionsOrNoExpected() {
        RestrictionAllocation.Reconciliation none = RestrictionAllocation.reconcile(100000, new List<Restriction__c>());
        System.assert(none.status.startsWith('No restrictions'), none.status);
        System.assertEquals(100000, none.unallocated, 'all unallocated');

        RestrictionAllocation.Reconciliation noExp = RestrictionAllocation.reconcile(null, new List<Restriction__c>{ withYears(100000, null) });
        System.assert(noExp.status.startsWith('Cannot evaluate'), noExp.status);
    }
}