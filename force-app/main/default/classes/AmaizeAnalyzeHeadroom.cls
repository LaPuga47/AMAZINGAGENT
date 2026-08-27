/**
 * AmaizeAnalyzeHeadroom — the governed Headroom aggregation action for the Headroom
 * Analysis sub-agent.
 *
 * Given a Headroom category/program, a country, and (optionally) a fiscal year, it resolves
 * the governed Budget Line population (HR-001..HR-007 via HeadroomCategoryResolver) and sums
 * the eight governed financial fields across ALL qualifying Budget Lines in the current
 * scenario — it does not pick one line, average, or recalculate the stored headroom fields.
 * It reports the line count and derives Headroom Status from the summed Secured Headroom.
 *
 * Governed zero categories (Unrestricted / Working Capital) return zeros with status "Not
 * Applicable"; unconfigured categories say so; and "no qualifying lines" is reported as such,
 * never as a financial value of zero. Read-only. Scalar I/O.
 */
public with sharing class AmaizeAnalyzeHeadroom {

    public class Request {
        @InvocableVariable(label='Program' description='Headroom category / program, e.g. Core Program, Rural Retail, Market Access, Trees, System Change Extension, Unrestricted, Working Capital.' required=true)
        public String program;
        @InvocableVariable(label='Country' description='Country of the Budget Lines, e.g. Kenya. Authoritative filter.' required=true)
        public String country;
        @InvocableVariable(label='Fiscal Year' description='Fiscal year, e.g. 2027. Defaults to the current scenario when omitted.' required=false)
        public Integer fiscalYear;
    }

    public class Result {
        @InvocableVariable(label='Summary' description='Governed Headroom aggregation to show the user (all eight financial fields + line count + interpretation).')
        public String summary;
        @InvocableVariable(label='Signal' description='Headroom Status when found (Headroom Available / Some Headroom Available / Headroom Unavailable), or Not Applicable / NONE / NOT_CONFIGURED / NEEDS_INFO.')
        public String signal;
        @InvocableVariable(label='Headroom JSON' description='Machine-readable aggregated Headroom detail.')
        public String headroomJson;
        @InvocableVariable(label='Found' description='True when the request resolved to a governed result (aggregated lines or a governed zero category).')
        public Boolean found;
    }

    @InvocableMethod(
        label='Analyze Budget Line Headroom'
        description='Resolves a Headroom category/program to its governed Budget Line population and sums Budget Amount, Secured/Likely/Pipeline/Forecast Funding, Secured/Forecast Headroom, and Headroom Status across all qualifying lines for a country and fiscal year.')
    public static List<Result> analyze(List<Request> requests) {
        List<Result> results = new List<Result>();
        HeadroomService service = new HeadroomService();
        for (Request req : requests) {
            results.add(answerOne(req, service));
        }
        return results;
    }

    private static Result answerOne(Request req, HeadroomService service) {
        String fy = (req.fiscalYear != null) ? String.valueOf(req.fiscalYear) : null;
        HeadroomAggregate a = service.aggregate(req.program, req.country, fy);

        Result r = new Result();
        switch on a.state {
            when FOUND {
                r.found = true;
                r.signal = a.headroomStatus;
                r.summary = foundSummary(a);
                r.headroomJson = foundJson(a);
            }
            when ZERO {
                r.found = true;
                r.signal = 'Not Applicable';
                r.summary = zeroSummary(a);
                r.headroomJson = '{"category":"' + a.category + '","status":"Not Applicable","budgetLinesIncluded":0}';
            }
            when NOT_CONFIGURED {
                r.found = false;
                r.signal = 'NOT_CONFIGURED';
                r.summary = 'The Headroom aggregation rule for "' + a.category
                    + '" has not yet been configured, so I can\'t compute it. '
                    + 'Please ask Grants Finance to configure a governed Salesforce mapping for that category.';
                r.headroomJson = '{"status":"NOT_CONFIGURED"}';
            }
            when NONE {
                r.found = false;
                r.signal = 'NONE';
                r.summary = 'No qualifying Budget Line records were found for the requested scope ('
                    + a.category + ', ' + a.country + (a.fiscalYear != null ? ', FY' + a.fiscalYear : '') + ').';
                r.headroomJson = '{"status":"NONE","budgetLinesIncluded":0}';
            }
            when else { // NEEDS_INFO
                r.found = false;
                r.signal = 'NEEDS_INFO';
                r.summary = 'I can run that Headroom aggregation. I still need the '
                    + HeadroomFormat.humanJoin(a.missing) + '.';
                r.headroomJson = '{"status":"NEEDS_INFO"}';
            }
        }
        return r;
    }

    private static String foundSummary(HeadroomAggregate a) {
        String iso = a.currencyIsoCode;
        String header = '**' + a.category + ' — ' + a.country
            + (a.fiscalYear != null ? ' — FY' + a.fiscalYear : '')
            + (a.scenarioLabel != null ? ' (' + a.scenarioLabel + ')' : '') + '**';

        String figures = '\n\n'
            + '- Budget Amount: ' + AmaizeFormat.money(a.budgetAmount, iso) + '\n'
            + '- Secured Funding: ' + AmaizeFormat.money(a.securedFunding, iso) + '\n'
            + '- Likely Funding: ' + AmaizeFormat.money(a.likelyFunding, iso) + '\n'
            + '- Pipeline Funding: ' + AmaizeFormat.money(a.pipelineFunding, iso) + '\n'
            + '- Forecast Funding: ' + AmaizeFormat.money(a.forecastFunding, iso) + '\n'
            + '- Secured Headroom: ' + AmaizeFormat.money(a.securedHeadroom, iso) + '\n'
            + '- Forecast Headroom: ' + AmaizeFormat.money(a.forecastHeadroom, iso) + '\n'
            + '- Headroom Status: ' + a.headroomStatus + '\n'
            + '- Budget Lines Included: ' + a.budgetLinesIncluded;

        // Concise interpretation, grounded in the summed governed figures.
        String interp;
        if (a.securedHeadroom < 0) {
            interp = 'This program is over-allocated on secured funding by '
                + AmaizeFormat.money(-a.securedHeadroom, iso) + ' across ' + a.budgetLinesIncluded
                + ' budget line' + (a.budgetLinesIncluded == 1 ? '' : 's') + '.';
        } else if (a.headroomStatus == 'Headroom Available') {
            interp = 'There is ' + AmaizeFormat.money(a.securedHeadroom, iso)
                + ' of secured headroom to raise against; forecast headroom after likely and pipeline funding is '
                + AmaizeFormat.money(a.forecastHeadroom, iso) + '.';
        } else {
            interp = 'Secured headroom is tight at ' + AmaizeFormat.money(a.securedHeadroom, iso)
                + '; confirm with Grants Finance before pitching. Forecast headroom is '
                + AmaizeFormat.money(a.forecastHeadroom, iso) + '.';
        }
        return header + figures + '\n\n' + interp;
    }

    private static String zeroSummary(HeadroomAggregate a) {
        return '**' + a.category + ' — ' + a.country + '**\n\n'
            + 'For the governed Headroom use case, ' + a.category + ' is defined as zero:\n'
            + '- Budget Amount: ' + AmaizeFormat.money(0, null) + '\n'
            + '- Secured Funding: ' + AmaizeFormat.money(0, null) + '\n'
            + '- Likely Funding: ' + AmaizeFormat.money(0, null) + '\n'
            + '- Pipeline Funding: ' + AmaizeFormat.money(0, null) + '\n'
            + '- Forecast Funding: ' + AmaizeFormat.money(0, null) + '\n'
            + '- Secured Headroom: ' + AmaizeFormat.money(0, null) + '\n'
            + '- Forecast Headroom: ' + AmaizeFormat.money(0, null) + '\n'
            + '- Headroom Status: Not Applicable';
    }

    private static String foundJson(HeadroomAggregate a) {
        return JSON.serialize(new Map<String, Object>{
            'category' => a.category, 'country' => a.country, 'fiscalYear' => a.fiscalYear,
            'scenario' => a.scenarioLabel,
            'budgetAmount' => a.budgetAmount, 'securedFunding' => a.securedFunding,
            'likelyFunding' => a.likelyFunding, 'pipelineFunding' => a.pipelineFunding,
            'forecastFunding' => a.forecastFunding, 'securedHeadroom' => a.securedHeadroom,
            'forecastHeadroom' => a.forecastHeadroom, 'headroomStatus' => a.headroomStatus,
            'budgetLinesIncluded' => a.budgetLinesIncluded
        });
    }
}
