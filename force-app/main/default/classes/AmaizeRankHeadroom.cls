/**
 * AmaizeRankHeadroom — portfolio ranking at the GOVERNED PROGRAM level for the Headroom
 * Analysis subagent.
 *
 * Answers "which programs and countries have the largest funding gap / most headroom in
 * FY2029?" by aggregating all qualifying Budget Lines into (Country + governed Headroom
 * Category + Fiscal Year) groups and ranking the AGGREGATES — never individual Budget Lines.
 * The response is a concise executive list (Country - Program: value); it does not expose
 * cost dimensions, per-row status, or record counts. Read-only. Scalar I/O.
 */
public with sharing class AmaizeRankHeadroom {

    private static final Integer DEFAULT_TOP = 8;

    public class Request {
        @InvocableVariable(
            label='Metric'
            description='What to rank by: "largest funding gap" / "most headroom" (default, forecast headroom), "over-allocated" (most over-funded), or "secured headroom".'
            required=false)
        public String metric;
        @InvocableVariable(label='Country' description='Optional: limit to one country, e.g. Kenya.' required=false)
        public String country;
        @InvocableVariable(label='Fiscal Year' description='Fiscal year, e.g. 2029. Defaults to the current scenario when omitted.' required=false)
        public Integer fiscalYear;
        @InvocableVariable(label='Category' description='Optional: limit to one Headroom category, e.g. Core Program, Trees.' required=false)
        public String category;
        @InvocableVariable(label='Top N' description='How many program groups to return (default 8). Honor the user\'s requested limit if they give one.' required=false)
        public Integer topN;
    }

    public class Result {
        @InvocableVariable(label='Summary' description='Concise executive ranking of Country + Program funding gaps.')
        public String summary;
        @InvocableVariable(label='Match Count' description='How many governed program groups were returned.')
        public Integer matchCount;
        @InvocableVariable(label='Results JSON' description='Machine-readable aggregated program groups.')
        public String resultsJson;
    }

    @InvocableMethod(
        label='Rank Headroom Portfolio'
        description='Ranks governed Country + Program Headroom groups (aggregated across all qualifying Budget Lines) by funding gap / forecast headroom for portfolio questions like "which programs have the largest funding gap in FY2029?" Returns the top 8 by default.')
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
        Integer cap = (req.topN == null || req.topN <= 0) ? DEFAULT_TOP : req.topN;
        List<HeadroomAggregate> groups = service.rankPortfolioByCategory(
            req.metric, req.country, fy, req.category, cap);

        Result r = new Result();
        r.matchCount = groups.size();
        r.resultsJson = buildJson(groups);
        r.summary = buildSummary(req, groups);
        return r;
    }

    private static String buildSummary(Request req, List<HeadroomAggregate> groups) {
        Boolean overAlloc = req.metric != null &&
            (req.metric.toLowerCase().contains('over') || req.metric.toLowerCase().contains('alloc')
             || req.metric.toLowerCase().contains('tight'));
        Boolean secured = req.metric != null && req.metric.toLowerCase().contains('secured');
        String fyText = (req.fiscalYear != null) ? String.valueOf(req.fiscalYear)
            : (groups.isEmpty() || groups[0].fiscalYear == null ? 'the current scenario' : groups[0].fiscalYear);
        String catText = String.isNotBlank(req.category) ? ' ' + req.category : '';
        String countryText = String.isNotBlank(req.country) ? ' in ' + req.country : '';

        if (groups.isEmpty()) {
            return 'No Headroom program groups were found for ' + fyText + countryText + catText + '.';
        }

        String measure = secured ? 'Secured Headroom' : 'Forecast Headroom';
        String lead = overAlloc
            ? 'In ' + fyText + ', these' + catText + ' programs' + countryText + ' are the most over-allocated (by ' + measure + '):'
            : 'In ' + fyText + ', these' + catText + ' programs' + countryText + ' have the greatest funding need based on ' + measure + ':';

        List<String> lines = new List<String>();
        Integer i = 1;
        for (HeadroomAggregate a : groups) {
            String iso = a.currencyIsoCode;
            Decimal v = secured ? a.securedHeadroom : a.forecastHeadroom;
            String val = overAlloc ? AmaizeFormat.money(-v, iso) + ' over-allocated' : AmaizeFormat.money(v, iso);
            lines.add(i + '. ' + a.country + ' - ' + a.category + ': ' + val);
            i++;
        }
        String tail = '\n\nThese are the ' + groups.size() + ' largest ' + fyText
            + ' program-level ' + (overAlloc ? 'over-allocations' : 'funding gaps')
            + '. Ask "why is <country> <program> so high?" for the breakdown, or name one for its full headroom.';
        return lead + '\n' + String.join(lines, '\n') + tail;
    }

    private static String buildJson(List<HeadroomAggregate> groups) {
        List<Map<String, Object>> rows = new List<Map<String, Object>>();
        for (HeadroomAggregate a : groups) {
            rows.add(new Map<String, Object>{
                'country' => a.country, 'category' => a.category, 'fiscalYear' => a.fiscalYear,
                'budgetLinesIncluded' => a.budgetLinesIncluded, 'budgetAmount' => a.budgetAmount,
                'securedFunding' => a.securedFunding, 'likelyFunding' => a.likelyFunding,
                'pipelineFunding' => a.pipelineFunding, 'forecastFunding' => a.forecastFunding,
                'securedHeadroom' => a.securedHeadroom, 'forecastHeadroom' => a.forecastHeadroom,
                'headroomStatus' => a.headroomStatus
            });
        }
        return JSON.serialize(rows);
    }
}
