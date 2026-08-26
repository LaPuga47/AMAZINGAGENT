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

    /** Allocations directly linked to any of the given Budget Lines (multi-line scope). */
    List<Allocation__c> byBudgetLineIds(Set<Id> budgetLineIds);

    /** Not-yet-linked allocations whose Match Key equals any of the given Budget Line keys. */
    List<Allocation__c> byMatchKeysUnlinked(Set<String> matchKeys);

    /** Allocations for a given Opportunity (via Restriction -> Gift Commitment -> Opportunity). */
    List<Allocation__c> byOpportunityId(Id opportunityId);
}
