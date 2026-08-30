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
        @InvocableVariable(label='Summary' description='The DEFAULT conversational answer to show the user: a concise 2-4 sentence business answer (available Headroom / funding position) plus a contextual follow-up. Present this by default; do NOT show the full field-by-field breakdown unless the user asks.')
        public String summary;
        @InvocableVariable(label='Detail' description='The full governed breakdown — all eight financial fields, Headroom Status, and Budget Lines Included. Show this ONLY when the user asks for the numbers, a breakdown, how it was calculated, secured vs forecast, pipeline/likely detail, or the Budget Lines.')
        public String detail;
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
                r.summary = foundConversational(a);   // default: concise business answer
                r.detail = foundDetail(a);            // full breakdown, on demand only
                r.headroomJson = foundJson(a);
            }
            when ZERO {
                r.found = true;
                r.signal = 'Not Applicable';
                r.summary = zeroConversational(a);
                r.detail = zeroDetail(a);
                r.headroomJson = '{"category":"' + a.category + '","status":"Not Applicable","budgetLinesIncluded":0}';
            }
            when NOT_CONFIGURED {
                r.found = false;
                r.signal = 'NOT_CONFIGURED';
                r.summary = 'The Headroom aggregation rule for "' + a.category
                    + '" has not yet been configured, so I can\'t compute it. '
                    + 'Please ask Grants Finance to configure a Headroom rule for that category.';
                r.detail = r.summary;
                r.headroomJson = '{"status":"NOT_CONFIGURED"}';
            }
            when NONE {
                r.found = false;
                r.signal = 'NONE';
                r.summary = 'No qualifying Budget Line records were found for the requested scope ('
                    + a.category + ', ' + a.country + (a.fiscalYear != null ? ', ' + a.fiscalYear : '') + ').';
                r.detail = r.summary;
                r.headroomJson = '{"status":"NONE","budgetLinesIncluded":0}';
            }
            when else { // NEEDS_INFO
                r.found = false;
                r.signal = 'NEEDS_INFO';
                r.summary = 'I can run that Headroom aggregation. I still need the '
                    + HeadroomFormat.humanJoin(a.missing) + '.';
                r.detail = r.summary;
                r.headroomJson = '{"status":"NEEDS_INFO"}';
            }
        }
        return r;
    }

    /**
     * The DEFAULT conversational answer — a concise business reply that leads with the
     * fundraising position and surfaces only the numbers that answer the question. Full
     * financial intelligence stays underneath (see foundDetail / headroomJson); this is the
     * simple answer on top. Every figure is drawn verbatim from the governed aggregate.
     */
    private static String foundConversational(HeadroomAggregate a) {
        String iso = a.currencyIsoCode;
        String name = naturalName(a);
        String fyText = (a.fiscalYear != null) ? a.fiscalYear : 'the current scenario';
        Decimal reducers = nz(a.likelyFunding) + nz(a.pipelineFunding);

        String body;
        if (a.forecastHeadroom < 0) {
            body = name + ' does not currently show available Headroom in ' + fyText
                + '. The program is approximately ' + AmaizeFormat.money(-a.forecastHeadroom, iso)
                + ' beyond its funding capacity under the current forecast.';
        } else if (a.forecastHeadroom == 0) {
            body = name + ' is currently fully funded in ' + fyText
                + ', with no additional Headroom available under the current forecast.';
        } else if (materialReducers(reducers, a.securedHeadroom) && a.securedHeadroom > a.forecastHeadroom) {
            // Secured and forecast headroom differ materially — both numbers are useful.
            body = 'There appears to be room for additional fundraising for ' + name + ' in ' + fyText
                + ', but it is tighter once likely and pipeline funding are considered. It has about '
                + AmaizeFormat.money(a.securedHeadroom, iso) + ' of Secured Headroom, which falls to roughly '
                + AmaizeFormat.money(a.forecastHeadroom, iso) + ' on a forecast basis.';
        } else {
            body = 'There appears to be room for additional fundraising for ' + name + ' in ' + fyText
                + ', with approximately ' + AmaizeFormat.money(a.forecastHeadroom, iso) + ' of available Headroom. '
                + fundingSentence(a, iso);
        }

        String note = scenarioMismatchNote(a);
        return body + (note != null ? '\n\n' + note : '') + '\n\n' + followUpFor(a, reducers);
    }

    /** "Around $27K is currently secured, with no likely or pipeline funding." */
    private static String fundingSentence(HeadroomAggregate a, String iso) {
        Decimal likely = nz(a.likelyFunding), pipeline = nz(a.pipelineFunding);
        String s = 'Around ' + AmaizeFormat.money(a.securedFunding, iso) + ' is currently secured';
        if (likely == 0 && pipeline == 0) {
            return s + ', with no likely or pipeline funding.';
        } else if (likely == 0 && pipeline != 0) {
            return s + ', with about ' + AmaizeFormat.money(pipeline, iso) + ' in pipeline funding.';
        } else if (likely != 0 && pipeline == 0) {
            return s + ', with about ' + AmaizeFormat.money(likely, iso) + ' in likely funding.';
        }
        return s + ', with ' + AmaizeFormat.money(likely, iso) + ' likely and '
            + AmaizeFormat.money(pipeline, iso) + ' pipeline funding.';
    }

    /** Contextual next step, chosen from the funding position — never the same generic line. */
    private static String followUpFor(HeadroomAggregate a, Decimal reducers) {
        if (a.forecastHeadroom <= 0) {
            return 'Would you like me to show which grants and allocations are consuming the current capacity?';
        }
        if (materialReducers(reducers, a.securedHeadroom) && a.securedHeadroom > a.forecastHeadroom) {
            return 'Would you like me to show which pipeline Opportunities are consuming the remaining Headroom?';
        }
        return 'Would you like me to show the grants already funding ' + a.category + ' in ' + a.country
            + ', or the Opportunities currently in the pipeline?';
    }

    /** Secured vs forecast headroom differ by a mention-worthy amount (i.e. likely+pipeline is material). */
    private static Boolean materialReducers(Decimal reducers, Decimal securedHeadroom) {
        Decimal r = Math.abs(reducers);
        return r >= 50000 && r >= 0.10 * Math.abs(securedHeadroom == 0 ? r : securedHeadroom);
    }

    private static String naturalName(HeadroomAggregate a) {
        // "Kenya Trees" — the country plus the canonical category, never internal Business Units.
        return a.country + ' ' + a.category;
    }

    private static String scenarioMismatchNote(HeadroomAggregate a) {
        if (a.scenarioLabel != null && a.fiscalYear != null && !a.scenarioLabel.contains(a.fiscalYear)) {
            return '_Note: these ' + a.fiscalYear + ' Budget Lines currently sit under a scenario named "'
                + a.scenarioLabel + '." You may want to confirm this is the intended planning scenario._';
        }
        return null;
    }

    private static String zeroConversational(HeadroomAggregate a) {
        return naturalName(a) + ' is defined as zero under the Headroom model, so there is no '
            + 'Headroom to raise against in ' + (a.fiscalYear != null ? a.fiscalYear : 'the current scenario') + '.';
    }

    private static Decimal nz(Decimal d) { return d == null ? 0 : d; }

    private static String foundDetail(HeadroomAggregate a) {
        String iso = a.currencyIsoCode;
        String header = '**' + a.category + ' — ' + a.country
            + (a.fiscalYear != null ? ' — ' + a.fiscalYear : '')
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

    private static String zeroDetail(HeadroomAggregate a) {
        return '**' + a.category + ' — ' + a.country + '**\n\n'
            + 'For the Headroom model, ' + a.category + ' is defined as zero:\n'
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
