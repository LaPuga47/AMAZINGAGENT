/**
 * AmaizePortfolioRisks — portfolio-level competing-grant risk action for the Competing Grants
 * Analysis sub-agent. Ranks governed scopes (Headroom category + country + fiscal year) across
 * the current scenario by collision risk, tightest headroom, or most competition — answering
 * "where are our biggest competing-grant risks?", "which countries have the tightest Core
 * Program headroom?", "show me the top 10 headroom collision risks".
 *
 * Scale-safe (two aggregate queries) and read-only. Scalar I/O.
 */
public with sharing class AmaizePortfolioRisks {

    public class Request {
        @InvocableVariable(label='Metric' description='How to rank: "collision risk" (default, largest potential over-allocation), "tightest headroom", or "most competition".' required=false)
        public String metric;
        @InvocableVariable(label='Category' description='Optional Headroom category to limit to, e.g. Core Program, Rural Retail, Trees.' required=false)
        public String category;
        @InvocableVariable(label='Country' description='Optional country to limit to, e.g. Kenya.' required=false)
        public String country;
        @InvocableVariable(label='Fiscal Year' description='Optional fiscal year, e.g. 2027. Defaults to all fiscal years in the current scenario.' required=false)
        public Integer fiscalYear;
        @InvocableVariable(label='Top N' description='How many scopes to return (default 10).' required=false)
        public Integer topN;
    }

    public class Result {
        @InvocableVariable(label='Summary' description='Ranked portfolio competing-grant risk to show the user.')
        public String summary;
        @InvocableVariable(label='Match Count' description='Number of governed scopes ranked.')
        public Integer matchCount;
        @InvocableVariable(label='Results JSON' description='Machine-readable ranked scopes.')
        public String resultsJson;
    }

    @InvocableMethod(
        label='Rank Portfolio Competing Risks'
        description='Ranks governed Headroom scopes (category + country + fiscal year) across the current scenario by competing-grant collision risk, tightest headroom, or most competition.')
    public static List<Result> rank(List<Request> requests) {
        List<Result> results = new List<Result>();
        PortfolioHeadroomService svc = new PortfolioHeadroomService();
        for (Request req : requests) {
            results.add(answerOne(req, svc));
        }
        return results;
    }

    private static Result answerOne(Request req, PortfolioHeadroomService svc) {
        String fy = (req.fiscalYear != null) ? String.valueOf(req.fiscalYear) : null;
        Integer cap = (req.topN == null || req.topN <= 0) ? 10 : req.topN;
        List<PortfolioScopeRisk> ranked = svc.rank(req.metric, req.category, req.country, fy, cap);

        Result r = new Result();
        r.matchCount = ranked.size();
        r.resultsJson = json(ranked);
        r.summary = compose(req, ranked);
        return r;
    }

    private static String compose(Request req, List<PortfolioScopeRisk> ranked) {
        String metricLabel = metricLabel(req.metric);
        String scopeFilter = '';
        if (String.isNotBlank(req.category)) { scopeFilter += ' · ' + req.category; }
        if (String.isNotBlank(req.country)) { scopeFilter += ' · ' + req.country; }
        if (req.fiscalYear != null) { scopeFilter += ' · ' + req.fiscalYear; }

        if (ranked.isEmpty()) {
            return 'No Headroom scopes were found for the current scenario' + scopeFilter + '.';
        }

        String header = '**Portfolio Competing-Grant Risk — ranked by ' + metricLabel + scopeFilter + '**'
            + '\n_Each row is a program scope (category · country · year); competing funding is '
            + 'Likely + Pipeline against secured headroom._';

        List<String> rows = new List<String>();
        for (PortfolioScopeRisk s : ranked) {
            String iso = s.currencyIsoCode;
            String risk = s.minimumAdjustmentRequired > 0
                ? AmaizeFormat.money(s.minimumAdjustmentRequired, iso) + ' over headroom'
                : AmaizeFormat.money(s.securedHeadroom - s.combinedCompeting, iso) + ' spare';
            rows.add('- **' + s.category + ' · ' + s.country
                + (s.fiscalYear != null ? ' · ' + s.fiscalYear : '') + '** — '
                + s.severity + '. Competing ' + AmaizeFormat.money(s.combinedCompeting, iso)
                + ' vs secured headroom ' + AmaizeFormat.money(s.securedHeadroom, iso)
                + ' (' + risk + '); ' + s.budgetLineCount + ' budget line'
                + (s.budgetLineCount == 1 ? '' : 's') + '.');
        }

        String footer = '\n\nName any scope — e.g. "competing grants for '
            + ranked[0].category + ' ' + ranked[0].country
            + (ranked[0].fiscalYear != null ? ' ' + ranked[0].fiscalYear : '')
            + '" — for the full breakdown with opportunities and record links.';

        return header + '\n\n' + String.join(rows, '\n') + footer;
    }

    private static String metricLabel(String metric) {
        String m = (metric == null) ? '' : metric.toLowerCase();
        if (m.contains('tight') || m.contains('least')) { return 'tightest secured headroom'; }
        if (m.contains('compet') || m.contains('most')) { return 'most competing exposure'; }
        return 'collision risk (largest potential over-allocation)';
    }

    private static String json(List<PortfolioScopeRisk> ranked) {
        List<Map<String, Object>> rows = new List<Map<String, Object>>();
        for (PortfolioScopeRisk s : ranked) {
            rows.add(new Map<String, Object>{
                'category' => s.category, 'country' => s.country, 'fiscalYear' => s.fiscalYear,
                'budgetLineCount' => s.budgetLineCount, 'securedHeadroom' => s.securedHeadroom,
                'forecastHeadroom' => s.forecastHeadroom, 'combinedCompeting' => s.combinedCompeting,
                'competingAllocationCount' => s.competingAllocationCount,
                'minimumAdjustmentRequired' => s.minimumAdjustmentRequired, 'severity' => s.severity
            });
        }
        return JSON.serialize(rows);
    }
}
