/**
 * AllocationBreakdown — the funding detail behind a Budget Line, summed by
 * Allocation_Type__c (Secured / Likely / Pipeline). Built from the Allocation__c
 * records associated with a single Budget Line (never merged across Budget Lines).
 *
 * The Budget Line's own stored fields remain the source of truth for the headroom
 * figures; this breakdown is the supporting "who / how much" detail and lets the
 * agent name the largest grant in play. Plain data holder — no SOQL, no DML.
 */
public with sharing class AllocationBreakdown {

    public Decimal securedTotal = 0;
    public Decimal likelyTotal = 0;
    public Decimal pipelineTotal = 0;

    public Integer securedCount = 0;
    public Integer likelyCount = 0;
    public Integer pipelineCount = 0;
    public Integer otherCount = 0;
    public Integer totalCount = 0;

    public String currencyIsoCode;

    // The single largest allocation and the grant behind it (for "what is eating headroom").
    public Decimal topAmount = 0;
    public String topGrantName;

    /** Sum a list of allocations for ONE Budget Line into a typed breakdown. */
    public static AllocationBreakdown fromList(List<Allocation__c> allocations) {
        AllocationBreakdown b = new AllocationBreakdown();
        if (allocations == null) {
            return b;
        }
        for (Allocation__c a : allocations) {
            Decimal amount = a.Funds_Allocated__c == null ? 0 : a.Funds_Allocated__c;
            String type = a.Allocation_Type__c;
            if (type == 'Secured') {
                b.securedTotal += amount; b.securedCount++;
            } else if (type == 'Likely') {
                b.likelyTotal += amount; b.likelyCount++;
            } else if (type == 'Pipeline') {
                b.pipelineTotal += amount; b.pipelineCount++;
            } else {
                b.otherCount++;
            }
            b.totalCount++;
            if (b.currencyIsoCode == null && a.CurrencyIsoCode != null) {
                b.currencyIsoCode = a.CurrencyIsoCode;
            }
            if (amount > b.topAmount) {
                b.topAmount = amount;
                b.topGrantName = grantName(a);
            }
        }
        return b;
    }

    /** The grant (Opportunity) name reached via Restriction -> Gift Commitment -> Opportunity, if loaded. */
    private static String grantName(Allocation__c a) {
        if (a.Restriction__r != null
                && a.Restriction__r.Gift_Commitment__r != null
                && a.Restriction__r.Gift_Commitment__r.Opportunity != null) {
            return a.Restriction__r.Gift_Commitment__r.Opportunity.Name;
        }
        return null;
    }
}
