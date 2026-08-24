/**
 * AmaizeRankHeadroom — the portfolio-level action for the Headroom Analysis subagent.
 *
 * Answers questions like "which programs in Kenya have the most headroom in FY2027?",
 * "where are the largest funding gaps?", or "which Budget Lines are over-allocated?".
 * It ranks the current-scenario Budget Lines by their stored Forecast Headroom and
 * lists each one WITH its distinguishing dimensions — it never merges Budget Lines
 * into a single aggregate unless explicitly asked (and this action never aggregates).
 *
 * Read-only. Scalar String/Integer I/O per Agentforce platform rules.
 */
public with sharing class AmaizeRankHeadroom {

    private static final Integer MAX_RESULTS = 15;

    /* ---------------- Action input ---------------- */
    public class Request {
        @InvocableVariable(
            label='Status Filter'
            description='What to rank: "most headroom"/"funding gap" (room to raise), "over-allocated" (over-funded), or "all".'
            required=true)
        public String statusFilter;

        @InvocableVariable(label='Country' description='Optional: limit to one country, e.g. Kenya.' required=false)
        public String country;

        @InvocableVariable(label='Fiscal Year' description='Optional: limit to one fiscal year, e.g. 2027.' required=false)
        public Integer fiscalYear;
    }

    /* ---------------- Action output ---------------- */
    public class Result {
        @InvocableVariable(label='Summary' description='Human-readable ranked list of Budget Lines to show the user.')
        public String summary;

        @InvocableVariable(label='Match Count' description='How many Budget Lines matched the filter.')
        public Integer matchCount;

        @InvocableVariable(label='Results JSON' description='Machine-readable ranked list of Budget Lines.')
        public String resultsJson;
    }

    @InvocableMethod(
        label='Rank Budget Line Headroom'
        description='Ranks current-scenario Budget Lines by headroom for portfolio questions like "which programs have the most headroom?" or "which Budget Lines are over-allocated?"')
    public static List<Result> rank(List<Request> requests) {
        List<Result> results = new List<Result>();
        HeadroomService service = new HeadroomService();
        for (Request req : requests) {
            results.add(answerOne(req, service));
        }
        return results;
    }

    private static Result answerOne(Request req, HeadroomService service) {
        String fy = (req.fiscalYear != null) ? String.valueOf(req.fiscalYear) : null;
        List<Budget_Line__c> ranked = service.rankPortfolio(req.country, fy, req.statusFilter);

        Result r = new Result();
        r.matchCount = ranked.size();
        r.resultsJson = buildJson(ranked);
        r.summary = buildSummary(req, ranked);
        return r;
    }

    private static String buildSummary(Request req, List<Budget_Line__c> ranked) {
        String scope = '';
        if (String.isNotBlank(req.country)) { scope += ' in ' + req.country; }
        if (req.fiscalYear != null) { scope += ' for FY' + req.fiscalYear; }

        if (ranked.isEmpty()) {
            return 'I found no Budget Lines matching that' + scope + ' in the current scenario.';
        }

        Integer shown = Math.min(ranked.size(), MAX_RESULTS);
        List<String> lines = new List<String>();
        for (Integer i = 0; i < shown; i++) {
            Budget_Line__c bl = ranked[i];
            String iso = bl.CurrencyIsoCode;
            Decimal fh = AmaizeBudgetHeadroom.nz(bl.Forecast_Headroom__c);
            String figure = (fh < 0)
                ? AmaizeFormat.money(-fh, iso) + ' over-allocated'
                : AmaizeFormat.money(fh, iso) + ' of headroom';
            lines.add('- **' + HeadroomFormat.lineLabel(bl) + '**: ' + figure
                + ' _(' + bl.Headroom_status__c + ')_');
        }

        String header = '**Found ' + ranked.size() + ' Budget Line'
            + (ranked.size() == 1 ? '' : 's') + scope + ', ranked by forecast headroom'
            + (ranked.size() > shown ? ' (showing the top ' + shown + ')' : '') + ':**';
        String footer = 'Name any one — with its fiscal year, country, business unit, and sub-unit — '
            + 'and I\'ll pull its full headroom breakdown.';

        return header + '\n\n' + String.join(lines, '\n') + '\n\n' + footer;
    }

    private static String buildJson(List<Budget_Line__c> ranked) {
        List<Map<String, Object>> rows = new List<Map<String, Object>>();
        Integer shown = Math.min(ranked.size(), MAX_RESULTS);
        for (Integer i = 0; i < shown; i++) {
            Budget_Line__c bl = ranked[i];
            rows.add(new Map<String, Object>{
                'fiscalYear' => bl.Fiscal_Year__c,
                'country' => bl.Country__c,
                'businessUnit' => bl.BusinessUnit__c,
                'subUnit' => bl.Sub__c,
                'department' => bl.Department__c,
                'costType' => bl.Cost_Type__c,
                'costCategory' => bl.Cost_Category__c,
                'currency' => bl.CurrencyIsoCode,
                'forecastHeadroom' => AmaizeBudgetHeadroom.nz(bl.Forecast_Headroom__c),
                'securedHeadroom' => AmaizeBudgetHeadroom.nz(bl.Secured_Headroom__c),
                'status' => bl.Headroom_status__c
            });
        }
        return JSON.serialize(rows);
    }
}
