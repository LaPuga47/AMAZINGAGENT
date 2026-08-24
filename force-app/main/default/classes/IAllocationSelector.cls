/**
 * IAllocationSelector — read-only query surface for Allocation__c, so the Headroom
 * service can be unit-tested against a stub. All implementations run in user mode.
 */
public interface IAllocationSelector {

    /** Allocations DIRECTLY related to a Budget Line via the Budget_Line__c lookup. */
    List<Allocation__c> byBudgetLineId(Id budgetLineId);

    /**
     * Allocations that resolve to a Budget Line through the approved Match Key but are
     * not (yet) directly linked — the fallback used only when no direct link exists.
     */
    List<Allocation__c> byMatchKeyUnlinked(String matchKey);
}
