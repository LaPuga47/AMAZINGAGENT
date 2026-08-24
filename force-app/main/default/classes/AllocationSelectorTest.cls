/**
 * Tests AllocationSelector's two lookups that mirror the approved
 * Allocation-to-Budget-Line relationship:
 *   byBudgetLineId       — the DIRECT Budget_Line__c lookup.
 *   byMatchKeyUnlinked   — the approved Match Key, for allocations not yet linked.
 */
@isTest
private class AllocationSelectorTest {

    @isTest
    static void byBudgetLineIdReturnsDirectlyLinkedAllocations() {
        Budget_Scenario__c s = HeadroomTestData.makeCurrentScenario();
        Budget_Line__c line = HeadroomTestData.makeLine(s.Id, 'Uganda', 'Farm Input Sales',
            'N/A', 'N/A', 'N/A', 'N/A', -1000000, 0, 0, 0);
        // Restriction dims use a Cost Category no Budget Line has, so the linking flow
        // will NOT overwrite the explicit direct link we set here.
        HeadroomTestData.makeAllocation('Secured', 500000, line.Id,
            'Kenya', 'Core Program - KE', 'N/A', 'N/A', 'N/A', 'N/A');

        Test.startTest();
        List<Allocation__c> direct = new AllocationSelector().byBudgetLineId(line.Id);
        Test.stopTest();

        System.assertEquals(1, direct.size(), 'Should find the directly-linked allocation');
        System.assertEquals('Secured', direct[0].Allocation_Type__c);
    }

    @isTest
    static void byBudgetLineIdNullReturnsEmpty() {
        System.assertEquals(0, new AllocationSelector().byBudgetLineId(null).size());
    }

    @isTest
    static void byMatchKeyFindsUnlinkedAllocation() {
        Budget_Scenario__c s = HeadroomTestData.makeCurrentScenario();

        // 1) Create the allocation BEFORE the matching Budget Line exists, so the linking
        //    flow finds no match and leaves Budget_Line__c null.
        HeadroomTestData.makeAllocation('Likely', 200000, null,
            'Kenya', 'Core Program - KE', 'N/A', 'N/A', 'N/A', 'N/A');

        // 2) Now create the Budget Line whose composite key equals that match key.
        Budget_Line__c line = HeadroomTestData.makeLine(s.Id, 'Kenya', 'Core Program - KE',
            'N/A', 'N/A', 'N/A', 'N/A', -800000, 100000, 0, 0);

        Test.startTest();
        List<Allocation__c> direct = new AllocationSelector().byBudgetLineId(line.Id);
        List<Allocation__c> viaKey = new AllocationSelector().byMatchKeyUnlinked(line.Budget_Line_Unique_Key__c);
        Test.stopTest();

        System.assertEquals(0, direct.size(), 'No direct link should exist yet');
        System.assertEquals(1, viaKey.size(), 'Match Key should resolve the unlinked allocation');
        System.assertEquals('Likely', viaKey[0].Allocation_Type__c);
    }

    @isTest
    static void byMatchKeyBlankReturnsEmpty() {
        System.assertEquals(0, new AllocationSelector().byMatchKeyUnlinked('  ').size());
    }
}
