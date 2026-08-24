/**
 * HeadroomService — the Budget-Line-first headroom engine shared by the agent actions.
 *
 * It enforces the core design principle: DO NOT start from allocations. The sequence is
 *   1. normalize the supplied dimensions,
 *   2. confirm the minimum information is present,
 *   3. identify the intended Budget Line (exact composite key when all seven dimensions
 *      are given, otherwise a progressive structured search),
 *   4. only then retrieve the allocations associated with THAT Budget Line
 *      (direct lookup first, approved Match Key second),
 *   5. read headroom from the Budget Line's own stored/calculated fields.
 *
 * It never merges unrelated Budget Lines: multiple matches produce an AMBIGUOUS result
 * that reports the distinguishing dimensions so the user can choose. Read-only: no DML.
 */
public with sharing class HeadroomService {

    private final IBudgetLineSelector lines;
    private final IAllocationSelector allocations;

    // Dimension fields ranked most-specific first, for describing how candidates differ.
    private static final List<String> DIMENSION_FIELDS = new List<String>{
        'Cost_Category__c', 'Cost_Type__c', 'Department__c', 'Sub__c',
        'BusinessUnit__c', 'Country__c', 'Fiscal_Year__c'
    };

    public HeadroomService() {
        this(new BudgetLineSelector(), new AllocationSelector());
    }

    /** Dependency-injecting constructor, for unit tests with stub selectors. */
    public HeadroomService(IBudgetLineSelector lines, IAllocationSelector allocations) {
        this.lines = lines;
        this.allocations = allocations;
    }

    /**
     * Identify a single Budget Line from the supplied dimensions and, when found,
     * attach its allocation breakdown. Returns a NEEDS_INFO / AMBIGUOUS / NOT_FOUND
     * result instead of guessing whenever a specific line can't be pinned down.
     */
    public HeadroomAnalysis analyze(BudgetLineDimensions raw) {
        HeadroomAnalysis result = new HeadroomAnalysis();
        BudgetLineDimensions d = (raw == null ? new BudgetLineDimensions() : raw).normalize();
        result.requested = d;

        // Step 2 — minimum information check.
        if (!d.hasRequiredMinimum()) {
            result.status = HeadroomAnalysis.Status.NEEDS_INFO;
            result.missingDimensions = d.missingRequired();
            result.subUnitMissing = (d.subUnit == null);
            return result;
        }

        // Step 3 — identify the Budget Line. Exact key when fully specified, else progressive.
        List<Budget_Line__c> hits = d.hasAllSevenDimensions()
            ? lines.findByUniqueKey(HeadroomKeyBuilder.build(d))
            : lines.findByDimensions(d);

        if (hits == null || hits.isEmpty()) {
            result.status = HeadroomAnalysis.Status.NOT_FOUND;
            return result;
        }

        // Step 4 — ambiguity: never aggregate unrelated Budget Lines; ask instead.
        if (hits.size() > 1) {
            result.status = HeadroomAnalysis.Status.AMBIGUOUS;
            result.candidates = hits;
            result.distinguishingDimensions = distinguishingDimensions(hits);
            // Sub-Unit not supplied is the most common reason for multiple matches; flag it.
            result.subUnitMissing = (d.subUnit == null);
            return result;
        }

        // Exactly one Budget Line — attach its allocations (direct first, then Match Key).
        Budget_Line__c line = hits[0];
        result.line = line;
        attachAllocations(result, line);
        result.status = HeadroomAnalysis.Status.FOUND;
        return result;
    }

    /** Retrieve the allocations for ONE Budget Line, direct relationship taking priority. */
    private void attachAllocations(HeadroomAnalysis result, Budget_Line__c line) {
        List<Allocation__c> direct = allocations.byBudgetLineId(line.Id);
        if (!direct.isEmpty()) {
            result.allocations = AllocationBreakdown.fromList(direct);
            result.allocationSource = 'direct';
            return;
        }
        List<Allocation__c> viaKey = String.isBlank(line.Budget_Line_Unique_Key__c)
            ? new List<Allocation__c>()
            : allocations.byMatchKeyUnlinked(line.Budget_Line_Unique_Key__c);
        if (!viaKey.isEmpty()) {
            result.allocations = AllocationBreakdown.fromList(viaKey);
            result.allocationSource = 'match-key';
            return;
        }
        result.allocations = new AllocationBreakdown();
        result.allocationSource = 'none';
    }

    /**
     * For an ambiguous match, list the dimensions on which the candidates actually
     * differ, e.g. "Cost Category: Input Costs, Overhead Costs, Staff Costs".
     */
    private List<String> distinguishingDimensions(List<Budget_Line__c> candidates) {
        List<String> out = new List<String>();
        for (String field : DIMENSION_FIELDS) {
            Set<String> values = new Set<String>();
            for (Budget_Line__c bl : candidates) {
                Object v = bl.get(field);
                values.add(v == null ? '(blank)' : String.valueOf(v));
            }
            if (values.size() > 1) {
                List<String> sorted = new List<String>(values);
                sorted.sort();
                out.add(HeadroomFormat.dimensionLabel(field) + ': ' + String.join(sorted, ', '));
            }
        }
        return out;
    }

    /**
     * Portfolio ranking: return the current-scenario Budget Lines (optionally scoped by
     * country / fiscal year), filtered by intent and sorted by Forecast Headroom.
     * Budget Lines are NEVER merged — each row keeps its own dimensions.
     *   mode containing over/surplus/red  -> only over-allocated lines, most negative first
     *   mode containing gap/room/need/... -> only lines with headroom, most positive first
     *   otherwise ("all")                 -> every line, most headroom first
     */
    public List<Budget_Line__c> rankPortfolio(String country, String fiscalYear, String mode) {
        List<Budget_Line__c> all = lines.findPortfolio(country, fiscalYear);
        String m = (mode == null) ? 'all' : mode.toLowerCase();
        Boolean wantOver = m.contains('over') || m.contains('surplus') || m.contains('red')
            || m.contains('allocated');
        Boolean wantGap = m.contains('gap') || m.contains('room') || m.contains('most')
            || m.contains('need') || m.contains('green') || m.contains('available') || m.contains('raise');

        List<Budget_Line__c> filtered = new List<Budget_Line__c>();
        for (Budget_Line__c bl : all) {
            Decimal fh = AmaizeBudgetHeadroom.nz(bl.Forecast_Headroom__c);
            if (wantOver && fh >= 0) { continue; }
            if (wantGap && fh <= 0) { continue; }
            filtered.add(bl);
        }
        filtered.sort(new ByForecastHeadroom(wantOver));
        return filtered;
    }

    /**
     * Sort by Forecast Headroom. When ranking over-allocation, most-negative first;
     * otherwise most-positive (biggest room / biggest gap) first.
     */
    private class ByForecastHeadroom implements Comparator<Budget_Line__c> {
        private final Boolean ascending;
        ByForecastHeadroom(Boolean ascending) { this.ascending = ascending; }
        public Integer compare(Budget_Line__c a, Budget_Line__c b) {
            Decimal ha = AmaizeBudgetHeadroom.nz(a.Forecast_Headroom__c);
            Decimal hb = AmaizeBudgetHeadroom.nz(b.Forecast_Headroom__c);
            if (ha == hb) { return 0; }
            Boolean aFirst = ascending ? (ha < hb) : (ha > hb);
            return aFirst ? -1 : 1;
        }
    }
}
