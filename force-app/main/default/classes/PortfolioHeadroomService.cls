/**
 * PortfolioHeadroomService — portfolio-level competing-grant risk across many governed
 * scopes. It runs the governed category mapping independently for every
 * (Headroom category + country + fiscal year) present in the current scenario and ranks the
 * scopes by a chosen risk metric.
 *
 * Scale-safe: uses exactly TWO aggregate queries (budget-line rollup + competing-allocation
 * rollup), each grouped by Country/BusinessUnit/Department/FiscalYear, then rolls the rows
 * into governed categories in memory — no per-scope querying. Read-only: no DML.
 */
public with sharing class PortfolioHeadroomService {

    private final IBudgetLineSelector lines;
    private final IAllocationSelector allocations;

    public PortfolioHeadroomService() {
        this(new BudgetLineSelector(), new AllocationSelector());
    }
    public PortfolioHeadroomService(IBudgetLineSelector lines, IAllocationSelector allocations) {
        this.lines = lines;
        this.allocations = allocations;
    }

    /**
     * Ranked portfolio scopes. metric: 'tightest' (least secured headroom first),
     * 'competition' (most competing exposure first), else 'collision' (largest potential
     * over-allocation first — the default). Optional category / country / fiscalYear filters;
     * topN caps the result.
     */
    public List<PortfolioScopeRisk> rank(String metric, String categoryFilter, String country,
            String fiscalYear, Integer topN) {
        Map<String, PortfolioScopeRisk> byScope = new Map<String, PortfolioScopeRisk>();

        // 1) Budget-line rollup -> governed scopes.
        for (AggregateResult ar : lines.aggregatePortfolio(country, fiscalYear)) {
            String cat = HeadroomCategoryResolver.categoryForBudgetLine(
                (String) ar.get('bu'), (String) ar.get('dept'));
            if (cat == null) { continue; }                       // not a governed category
            if (String.isNotBlank(categoryFilter) && !cat.equalsIgnoreCase(canonical(categoryFilter))) { continue; }
            PortfolioScopeRisk s = scopeFor(byScope, cat, (String) ar.get('c'), (String) ar.get('fy'));
            s.addBudgetLines((Decimal) ar.get('sh'), (Decimal) ar.get('fh'),
                (Integer) ar.get('cnt'), (String) ar.get('iso'));
        }

        // 2) Competing-allocation rollup -> same scopes (only scopes with budget lines count).
        for (AggregateResult ar : allocations.aggregateCompetingPortfolio(country, fiscalYear)) {
            String cat = HeadroomCategoryResolver.categoryForBudgetLine(
                (String) ar.get('bu'), (String) ar.get('dept'));
            if (cat == null) { continue; }
            String key = key(cat, (String) ar.get('c'), (String) ar.get('fy'));
            PortfolioScopeRisk s = byScope.get(key);
            if (s == null) { continue; }                          // competition without a budget line -> skip
            s.addCompeting((Decimal) ar.get('amt'), (Integer) ar.get('cnt'));
        }

        List<PortfolioScopeRisk> out = new List<PortfolioScopeRisk>();
        for (PortfolioScopeRisk s : byScope.values()) {
            s.finalizeMetrics();
            out.add(s);
        }
        out.sort(comparatorFor(metric));

        Integer cap = (topN == null || topN <= 0) ? 10 : topN;
        if (out.size() > cap) {
            List<PortfolioScopeRisk> trimmed = new List<PortfolioScopeRisk>();
            for (Integer i = 0; i < cap; i++) { trimmed.add(out[i]); }
            return trimmed;
        }
        return out;
    }

    /** Resolve a user's category wording to its canonical label (via the governed resolver). */
    private String canonical(String categoryFilter) {
        HeadroomCategoryResolver.Rule rule = HeadroomCategoryResolver.resolve(categoryFilter);
        return (rule == null) ? categoryFilter : rule.label;
    }

    private PortfolioScopeRisk scopeFor(Map<String, PortfolioScopeRisk> byScope, String cat, String country, String fy) {
        String k = key(cat, country, fy);
        PortfolioScopeRisk s = byScope.get(k);
        if (s == null) {
            s = new PortfolioScopeRisk();
            s.category = cat; s.country = country; s.fiscalYear = fy;
            byScope.put(k, s);
        }
        return s;
    }

    private String key(String cat, String country, String fy) {
        return cat + '||' + country + '||' + fy;
    }

    private Comparator<PortfolioScopeRisk> comparatorFor(String metric) {
        String m = (metric == null) ? '' : metric.toLowerCase();
        if (m.contains('tight') || m.contains('least')) { return new ByTightestHeadroom(); }
        if (m.contains('compet') || m.contains('most')) { return new ByMostCompetition(); }
        return new ByCollisionRisk();
    }

    // Largest potential over-allocation first; tie-break by tighter headroom.
    private class ByCollisionRisk implements Comparator<PortfolioScopeRisk> {
        public Integer compare(PortfolioScopeRisk a, PortfolioScopeRisk b) {
            if (a.minimumAdjustmentRequired != b.minimumAdjustmentRequired) {
                return (b.minimumAdjustmentRequired > a.minimumAdjustmentRequired) ? 1 : -1;
            }
            if (a.securedHeadroom == b.securedHeadroom) { return 0; }
            return (a.securedHeadroom < b.securedHeadroom) ? -1 : 1;
        }
    }
    // Least secured headroom first (most negative / tightest).
    private class ByTightestHeadroom implements Comparator<PortfolioScopeRisk> {
        public Integer compare(PortfolioScopeRisk a, PortfolioScopeRisk b) {
            if (a.securedHeadroom == b.securedHeadroom) { return 0; }
            return (a.securedHeadroom < b.securedHeadroom) ? -1 : 1;
        }
    }
    // Most competing exposure first.
    private class ByMostCompetition implements Comparator<PortfolioScopeRisk> {
        public Integer compare(PortfolioScopeRisk a, PortfolioScopeRisk b) {
            if (a.combinedCompeting == b.combinedCompeting) { return 0; }
            return (b.combinedCompeting > a.combinedCompeting) ? 1 : -1;
        }
    }
}
