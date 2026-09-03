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

        // Step 3 — identify the Budget Line. When all seven dimensions are given, try the
        // exact composite key first (fast, unambiguous). Fall back to the structured search
        // if the key finds nothing — the key is exact on BusinessUnit__c, so a base name
        // like "Core Program" won't key-match the org's suffixed "Core Program - KE", but
        // the structured search applies the business-unit suffix tolerance.
        List<Budget_Line__c> hits;
        if (d.hasAllSevenDimensions()) {
            hits = lines.findByUniqueKey(HeadroomKeyBuilder.build(d));
            if (hits == null || hits.isEmpty()) {
                hits = lines.findByDimensions(d);
            }
        } else {
            hits = lines.findByDimensions(d);
        }

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

    /**
     * Governed Headroom aggregation (HR-001..HR-007). Resolves the category to its Budget
     * Line population, sums the eight governed financial fields across ALL qualifying lines
     * in the current scenario, counts them, and derives the aggregate Headroom Status from
     * the summed Secured Headroom (a status is derived, never summed). Country is the
     * authoritative filter; fiscal year defaults to the current scenario when omitted.
     * Never treats "no qualifying lines" as zero.
     */
    public HeadroomAggregate aggregate(String program, String country, String fiscalYear) {
        HeadroomAggregate a = new HeadroomAggregate();
        String cat = program == null ? '' : program.trim();
        String ctry = country == null ? '' : country.trim();
        if (cat == '') { a.missing.add('headroom category'); }
        if (ctry == '') { a.missing.add('country'); }
        if (!a.missing.isEmpty()) { a.state = HeadroomAggregate.State.NEEDS_INFO; return a; }

        HeadroomCategoryResolver.Rule rule = HeadroomCategoryResolver.resolve(cat);
        a.category = rule.label;
        a.country = ctry;

        // Governed zero categories (Unrestricted / Working Capital): return zeros, not a search.
        if (rule.mode == HeadroomCategoryResolver.Mode.ZERO) {
            a.state = HeadroomAggregate.State.ZERO;
            a.headroomStatus = 'Not Applicable';
            return a;
        }
        if (rule.mode == HeadroomCategoryResolver.Mode.NOT_CONFIGURED) {
            a.state = HeadroomAggregate.State.NOT_CONFIGURED;
            return a;
        }

        // Resolve the current scenario (its fiscal year defaults the filter; also reported).
        Budget_Scenario__c scenario = currentScenario();
        String fy = String.isNotBlank(fiscalYear) ? fiscalYear.trim()
                    : (scenario != null ? scenario.Fiscal_Year__c : null);
        a.fiscalYear = fy;
        a.scenarioLabel = (scenario != null)
            ? (scenario.Scenario_Type__c != null ? scenario.Scenario_Type__c + ' ' : '')
                + (scenario.Fiscal_Year__c != null ? 'FY' + scenario.Fiscal_Year__c : '')
            : null;

        BudgetLineDimensions d = new BudgetLineDimensions();
        d.country = ctry;
        d.fiscalYear = fy;
        d.businessUnit = rule.businessUnitBase;
        d.department = rule.department;   // required Department filter for RRT/MKT/TRE; null otherwise
        d = d.normalize();

        AggregateResult ar = lines.aggregateScope(d);
        Integer cnt = (ar == null) ? 0 : (Integer) ar.get('cnt');
        if (cnt == 0) {
            a.state = HeadroomAggregate.State.NONE;
            return a;
        }

        // SUM the governed fields (Budget Amount presented as a positive cost).
        a.budgetAmount = AmaizeBudgetHeadroom.budgetCost((Decimal) ar.get('bud'));
        a.securedFunding = AmaizeBudgetHeadroom.nz((Decimal) ar.get('sec'));
        a.likelyFunding = AmaizeBudgetHeadroom.nz((Decimal) ar.get('lik'));
        a.pipelineFunding = AmaizeBudgetHeadroom.nz((Decimal) ar.get('pipe'));
        a.forecastFunding = AmaizeBudgetHeadroom.nz((Decimal) ar.get('fcf'));
        a.securedHeadroom = AmaizeBudgetHeadroom.nz((Decimal) ar.get('sh'));
        a.forecastHeadroom = AmaizeBudgetHeadroom.nz((Decimal) ar.get('fh'));
        a.budgetLinesIncluded = cnt;
        a.currencyIsoCode = (String) ar.get('iso');
        // Headroom Status derived from the summed Secured Headroom (governed threshold rule).
        a.headroomStatus = AmaizeBudgetHeadroom.statusFor(a.securedHeadroom);
        a.state = HeadroomAggregate.State.FOUND;
        return a;
    }

    /** Outcome of the next-available-year lookahead (chronological search for the first future year with room). */
    public class NextAvailableYear {
        public Boolean found = false;
        public String year;                 // the earliest future year with available Headroom
        public Decimal availableHeadroom;    // that year's Forecast Headroom (positive)
        public String headroomStatus;
        public String currencyIsoCode;
        public List<String> yearsChecked = new List<String>();   // the future years actually evaluated, ascending
    }

    /**
     * NEXT-AVAILABLE-YEAR LOOKAHEAD. When the requested year has no available Headroom (fully
     * funded or overfunded), find the EARLIEST future year in which the SAME country + program
     * has available Headroom (Forecast Headroom > 0). It reuses aggregate() per candidate year —
     * no separate headroom calculation — and only searches years for which current-scenario
     * Budget Line data actually exists (no hard-coded horizon). Returns found=false when no
     * future year qualifies; the caller then falls back to other countries / other programs.
     */
    public NextAvailableYear findNextAvailableYear(String program, String country, String fromYear) {
        NextAvailableYear n = new NextAvailableYear();
        if (String.isBlank(program) || String.isBlank(country) || String.isBlank(fromYear)) { return n; }
        Integer fromY;
        try { fromY = Integer.valueOf(fromYear.trim()); } catch (Exception e) { return n; }

        for (String y : lines.distinctFiscalYears(country.trim())) {
            Integer yi;
            try { yi = Integer.valueOf(y); } catch (Exception e) { continue; }
            if (yi <= fromY) { continue; }                     // only look FORWARD, chronologically
            n.yearsChecked.add(y);
            HeadroomAggregate a = aggregate(program, country, y);
            if (a.state == HeadroomAggregate.State.FOUND && a.forecastHeadroom > 0) {
                n.found = true;
                n.year = y;
                n.availableHeadroom = a.forecastHeadroom;
                n.headroomStatus = a.headroomStatus;
                n.currencyIsoCode = a.currencyIsoCode;
                return n;                                     // stop at the FIRST qualifying year
            }
        }
        return n;
    }

    /**
     * DIMENSION MODE and PROGRAM + DIMENSION. Aggregates the same eight stored Budget Line
     * fields as aggregate(), but filtered by explicit lower-level dimensions rather than (or in
     * addition to) a standard Headroom program:
     *   - program only        -> Program Mode (use aggregate() instead; kept here for completeness)
     *   - dimension value only -> Dimension Mode (filter Budget Lines by that dimension)
     *   - program + dimension  -> resolve the program population, then segment by the dimension
     * A dimension VALUE with no explicit dimension name is auto-detected across Department /
     * Cost Category / Cost Type / Sub-Unit; if it exists in more than one, returns AMBIGUOUS; if
     * in none, returns NOT_FOUND. Country is required; fiscal year defaults to the current scenario.
     */
    public HeadroomAggregate aggregateExplicit(String program, String country, String fiscalYear,
            String dimName, String dimValue, String dim2Name, String dim2Value) {
        HeadroomAggregate a = new HeadroomAggregate();
        String ctry = country == null ? '' : country.trim();
        if (ctry == '') { a.missing.add('country'); a.state = HeadroomAggregate.State.NEEDS_INFO; return a; }
        a.country = ctry;

        Budget_Scenario__c scenario = currentScenario();
        String fy = String.isNotBlank(fiscalYear) ? fiscalYear.trim()
                    : (scenario != null ? scenario.Fiscal_Year__c : null);
        a.fiscalYear = fy;
        a.scenarioLabel = (scenario != null)
            ? (scenario.Scenario_Type__c != null ? scenario.Scenario_Type__c + ' ' : '')
                + (scenario.Fiscal_Year__c != null ? 'FY' + scenario.Fiscal_Year__c : '')
            : null;

        // Resolve the Budget Line population via the SHARED resolver — the identical logic
        // Competing Grants uses, so an explicit dimension resolves to the same lines everywhere.
        BudgetLineScopeResolver.Scope sc = BudgetLineScopeResolver.resolve(
            program, ctry, fy, dimName, dimValue, dim2Name, dim2Value, lines);
        a.category = sc.label;
        a.dimensionValue = sc.dimensionValue;
        if (sc.state == BudgetLineScopeResolver.State.ZERO) {
            a.state = HeadroomAggregate.State.ZERO; a.headroomStatus = 'Not Applicable'; return a;
        }
        if (sc.state == BudgetLineScopeResolver.State.NOT_CONFIGURED) {
            a.state = HeadroomAggregate.State.NOT_CONFIGURED; return a;
        }
        if (sc.state == BudgetLineScopeResolver.State.NEEDS_INFO) {
            a.missing.addAll(sc.missing); a.state = HeadroomAggregate.State.NEEDS_INFO; return a;
        }
        if (sc.state == BudgetLineScopeResolver.State.AMBIGUOUS) {
            a.candidateDimensions = sc.candidateDimensions; a.state = HeadroomAggregate.State.AMBIGUOUS; return a;
        }
        if (sc.state == BudgetLineScopeResolver.State.NOT_FOUND) {
            a.state = HeadroomAggregate.State.NOT_FOUND; return a;
        }

        AggregateResult ar = lines.aggregateScope(sc.dimensions);
        Integer cnt = (ar == null) ? 0 : (Integer) ar.get('cnt');
        if (cnt == 0) { a.state = HeadroomAggregate.State.NONE; return a; }

        a.budgetAmount = AmaizeBudgetHeadroom.budgetCost((Decimal) ar.get('bud'));
        a.securedFunding = AmaizeBudgetHeadroom.nz((Decimal) ar.get('sec'));
        a.likelyFunding = AmaizeBudgetHeadroom.nz((Decimal) ar.get('lik'));
        a.pipelineFunding = AmaizeBudgetHeadroom.nz((Decimal) ar.get('pipe'));
        a.forecastFunding = AmaizeBudgetHeadroom.nz((Decimal) ar.get('fcf'));
        a.securedHeadroom = AmaizeBudgetHeadroom.nz((Decimal) ar.get('sh'));
        a.forecastHeadroom = AmaizeBudgetHeadroom.nz((Decimal) ar.get('fh'));
        a.budgetLinesIncluded = cnt;
        a.currencyIsoCode = (String) ar.get('iso');
        a.headroomStatus = AmaizeBudgetHeadroom.statusFor(a.securedHeadroom);
        a.state = HeadroomAggregate.State.FOUND;
        return a;
    }

    /**
     * Portfolio ranking at the GOVERNED PROGRAM level (not individual Budget Lines). Rolls the
     * current-scenario Budget Lines up into (Country + governed Headroom Category + Fiscal Year)
     * groups — reusing the same category rules and stored fields as single-scope analysis, so a
     * ranked value equals a direct headroom query for that scope — sums the eight governed
     * fields per group, and ranks by the requested metric. Returns the top N (default 8).
     *
     * metric: "over"/"tight"/"allocated" -> most over-allocated first (forecast headroom asc);
     * "secured" -> most secured headroom first; anything else (largest funding gap / most
     * headroom / greatest need) -> most forecast headroom first.
     */
    public List<HeadroomAggregate> rankPortfolioByCategory(String metric, String country,
            String fiscalYear, String categoryFilter, Integer topN) {
        String fy = String.isNotBlank(fiscalYear) ? fiscalYear.trim() : null;
        if (fy == null) {
            Budget_Scenario__c sc = currentScenario();
            fy = (sc != null) ? sc.Fiscal_Year__c : null;
        }
        String wantCat = String.isBlank(categoryFilter) ? null : canonicalCategory(categoryFilter);

        Map<String, HeadroomAggregate> byScope = new Map<String, HeadroomAggregate>();
        for (AggregateResult ar : lines.aggregatePortfolio(country, fy)) {
            String cat = HeadroomCategoryResolver.categoryForBudgetLine(
                (String) ar.get('bu'), (String) ar.get('dept'));
            if (cat == null) { continue; }                       // not a governed category (or zero category)
            if (wantCat != null && !cat.equalsIgnoreCase(wantCat)) { continue; }
            String c = (String) ar.get('c');
            String gfy = (String) ar.get('fy');
            String key = cat + '||' + c + '||' + gfy;
            HeadroomAggregate a = byScope.get(key);
            if (a == null) {
                a = new HeadroomAggregate();
                a.state = HeadroomAggregate.State.FOUND;
                a.category = cat; a.country = c; a.fiscalYear = gfy;
                byScope.put(key, a);
            }
            a.budgetAmount += AmaizeBudgetHeadroom.budgetCost((Decimal) ar.get('bud'));
            a.securedFunding += AmaizeBudgetHeadroom.nz((Decimal) ar.get('sec'));
            a.likelyFunding += AmaizeBudgetHeadroom.nz((Decimal) ar.get('lik'));
            a.pipelineFunding += AmaizeBudgetHeadroom.nz((Decimal) ar.get('pipe'));
            a.forecastFunding += AmaizeBudgetHeadroom.nz((Decimal) ar.get('fcf'));
            a.securedHeadroom += AmaizeBudgetHeadroom.nz((Decimal) ar.get('sh'));
            a.forecastHeadroom += AmaizeBudgetHeadroom.nz((Decimal) ar.get('fh'));
            a.budgetLinesIncluded += (Integer) ar.get('cnt');
            if (a.currencyIsoCode == null) { a.currencyIsoCode = (String) ar.get('iso'); }
        }
        List<HeadroomAggregate> out = new List<HeadroomAggregate>();
        for (HeadroomAggregate a : byScope.values()) {
            a.headroomStatus = AmaizeBudgetHeadroom.statusFor(a.securedHeadroom);
            out.add(a);
        }
        out.sort(new ByHeadroomMetric(metric));
        Integer cap = (topN == null || topN <= 0) ? 8 : topN;
        if (out.size() > cap) {
            List<HeadroomAggregate> top = new List<HeadroomAggregate>();
            for (Integer i = 0; i < cap; i++) { top.add(out[i]); }
            return top;
        }
        return out;
    }

    /** Resolve a user's category wording to its canonical governed label. */
    private String canonicalCategory(String categoryFilter) {
        HeadroomCategoryResolver.Rule rule = HeadroomCategoryResolver.resolve(categoryFilter);
        return (rule == null) ? categoryFilter : rule.label;
    }

    /** Rank governed program groups by the requested headroom metric. */
    private class ByHeadroomMetric implements Comparator<HeadroomAggregate> {
        private final String mode;
        ByHeadroomMetric(String metric) { this.mode = (metric == null) ? '' : metric.toLowerCase(); }
        public Integer compare(HeadroomAggregate a, HeadroomAggregate b) {
            Boolean overAlloc = mode.contains('over') || mode.contains('tight') || mode.contains('alloc');
            Boolean secured = mode.contains('secured');
            Decimal va = secured ? a.securedHeadroom : a.forecastHeadroom;
            Decimal vb = secured ? b.securedHeadroom : b.forecastHeadroom;
            if (va == vb) { return 0; }
            if (overAlloc) { return (va < vb) ? -1 : 1; }   // most negative (over-allocated) first
            return (va > vb) ? -1 : 1;                        // most headroom / biggest gap first
        }
    }

    /** The current Budget Scenario (anchors the default fiscal year and the reported scenario). */
    private Budget_Scenario__c currentScenario() {
        List<Budget_Scenario__c> s = [
            SELECT Id, Fiscal_Year__c, Scenario_Type__c
            FROM Budget_Scenario__c
            WHERE Is_Current_Scenario__c = true
            WITH USER_MODE
            LIMIT 1
        ];
        return s.isEmpty() ? null : s[0];
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
