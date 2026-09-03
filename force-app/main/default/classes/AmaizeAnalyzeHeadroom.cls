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
        @InvocableVariable(label='Program' description='Standard Headroom category / program for PROGRAM MODE, e.g. Core Program, Rural Retail, Market Access, Trees, System Change Extension, Unrestricted, Working Capital. Leave blank for a pure DIMENSION MODE query. Providing both program and a dimension segments the program (Program + Dimension).' required=false)
        public String program;
        @InvocableVariable(label='Country' description='Country of the Budget Lines, e.g. Kenya. Authoritative filter. Required.' required=true)
        public String country;
        @InvocableVariable(label='Fiscal Year' description='Fiscal year, e.g. 2027. Defaults to the current scenario when omitted.' required=false)
        public Integer fiscalYear;
        @InvocableVariable(label='Dimension Value' description='DIMENSION MODE: an explicit Budget Line dimension value the user named, e.g. "Crop Insurance", "Staff Costs", "Field Operations". Pass this ONLY when the user asks about a specific lower-level dimension/item, not a standard program.' required=false)
        public String dimensionValue;
        @InvocableVariable(label='Dimension Name' description='Optional: the dimension the value belongs to — Department, Cost Category, Cost Type, Sub-Unit, or Business Unit. Pass it when the user is explicit (e.g. "Department = Market Access"); leave blank to auto-detect (the action asks if the value is ambiguous across dimensions).' required=false)
        public String dimensionName;
        @InvocableVariable(label='Second Dimension Value' description='Optional second explicit dimension value, for combined filters (e.g. Department = Market Access AND Cost Category = Staff Costs).' required=false)
        public String extraDimensionValue;
        @InvocableVariable(label='Second Dimension Name' description='Optional dimension name for the second value (Department / Cost Category / Cost Type / Sub-Unit / Business Unit).' required=false)
        public String extraDimensionName;
        @InvocableVariable(label='Part Of Range' description='Set true ONLY when this call is one year of an explicit multi-year RANGE the user asked for (e.g. "2027 to 2030"), so the per-year next-available-year lookahead is suppressed and you compose the year-by-year range answer yourself. Leave false/blank for a single-year question.' required=false)
        public Boolean partOfRange;
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
        Boolean dimensionMode = String.isNotBlank(req.dimensionValue) || String.isNotBlank(req.extraDimensionValue);
        HeadroomAggregate a = dimensionMode
            ? service.aggregateExplicit(req.program, req.country, fy, req.dimensionName, req.dimensionValue,
                                        req.extraDimensionName, req.extraDimensionValue)
            : service.aggregate(req.program, req.country, fy);   // Program Mode (unchanged path)

        Result r = new Result();
        switch on a.state {
            when FOUND {
                r.found = true;
                r.signal = a.headroomStatus;
                // NEXT-AVAILABLE-YEAR LOOKAHEAD: when a Program-Mode year has no available Headroom
                // (fully funded or overfunded), find the earliest future year that does. Skipped for
                // dimension mode and for individual years of an explicit multi-year range.
                HeadroomService.NextAvailableYear nextYear = null;
                if (!dimensionMode && String.isNotBlank(req.program) && a.forecastHeadroom <= 0
                        && req.partOfRange != true) {
                    nextYear = service.findNextAvailableYear(req.program, req.country, a.fiscalYear);
                }
                r.summary = foundConversational(a, nextYear);   // default: concise business answer
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
                r.summary = 'No qualifying Budget Line records were found for ' + a.category + ' in '
                    + a.country + (a.fiscalYear != null ? ' in ' + a.fiscalYear : '')
                    + ', so I cannot determine the funding gap.';
                r.detail = r.summary;
                r.headroomJson = '{"status":"NONE","budgetLinesIncluded":0}';
            }
            when AMBIGUOUS {
                r.found = false;
                r.signal = 'AMBIGUOUS';
                r.summary = '"' + a.dimensionValue + '" appears in more than one Budget Line dimension in '
                    + a.country + (a.fiscalYear != null ? ' in ' + a.fiscalYear : '')
                    + '. Do you mean ' + a.dimensionValue + ' as a '
                    + HeadroomFormat.humanJoin(a.candidateDimensions).replace(' and ', ' or ') + '?';
                r.detail = r.summary;
                r.headroomJson = '{"status":"AMBIGUOUS"}';
            }
            when NOT_FOUND {
                r.found = false;
                r.signal = 'NOT_FOUND';
                r.summary = 'I could not find "' + a.dimensionValue + '" in the available Budget Line '
                    + 'dimensions for ' + a.country + (a.fiscalYear != null ? ' in ' + a.fiscalYear : '') + '.';
                r.detail = r.summary;
                r.headroomJson = '{"status":"NOT_FOUND"}';
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
        return foundConversational(a, null);
    }

    private static String foundConversational(HeadroomAggregate a, HeadroomService.NextAvailableYear nextYear) {
        String iso = a.currencyIsoCode;
        String name = naturalName(a);
        String fyText = (a.fiscalYear != null) ? a.fiscalYear : 'the current scenario';
        Decimal reducers = nz(a.likelyFunding) + nz(a.pipelineFunding);

        // No available Headroom in the requested year: lead with the next fact-supported
        // fundraising option (same program + same country + next available year) when one exists.
        if (a.forecastHeadroom <= 0 && nextYear != null) {
            return noHeadroomWithLookahead(a, iso, name, fyText, nextYear);
        }

        String body;
        if (a.forecastHeadroom < 0) {
            body = name + ' is currently overfunded by approximately ' + AmaizeFormat.money(-a.forecastHeadroom, iso)
                + ' in ' + fyText + ' — funding exceeds its available capacity under the current forecast.';
        } else if (a.forecastHeadroom == 0) {
            body = name + ' is currently fully funded in ' + fyText
                + ', with no additional Headroom available under the current forecast.';
        } else if (materialReducers(reducers, a.securedHeadroom) && a.securedHeadroom > a.forecastHeadroom) {
            // Secured and forecast headroom differ materially — both numbers are useful.
            body = 'There appears to be room for additional fundraising for ' + name + ' in ' + fyText
                + ', but it is tighter once likely and pipeline funding are considered. It has about '
                + AmaizeFormat.money(a.securedHeadroom, iso) + ' of available Headroom now, which falls to roughly '
                + AmaizeFormat.money(a.forecastHeadroom, iso) + ' on a forecast basis.';
        } else {
            body = 'There appears to be room for additional fundraising for ' + name + ' in ' + fyText
                + ', with approximately ' + AmaizeFormat.money(a.forecastHeadroom, iso) + ' of available Headroom. '
                + fundingSentence(a, iso);
        }

        String note = scenarioMismatchNote(a);
        return body + (note != null ? '\n\n' + note : '') + '\n\n' + followUpFor(a, reducers);
    }

    /**
     * The no-available-Headroom answer, enriched with the next-available-year lookahead. When a
     * future year with room was found, lead the user there (same program + same country); when the
     * whole future horizon was searched with no room, say so and offer the other-country / other-
     * program alternatives. Never invents a future year — only reports what the lookahead verified.
     */
    private static String noHeadroomWithLookahead(HeadroomAggregate a, String iso, String name,
            String fyText, HeadroomService.NextAvailableYear nextYear) {
        String state = (a.forecastHeadroom < 0)
            ? name + ' has no available Headroom in ' + fyText + ' — it is currently overfunded by approximately '
                + AmaizeFormat.money(-a.forecastHeadroom, iso) + '.'
            : name + ' is fully funded in ' + fyText + ', with no available Headroom.';

        if (nextYear != null && nextYear.found) {
            String lead = state + ' The next year with available Headroom is ' + nextYear.year
                + ', with approximately ' + AmaizeFormat.money(nextYear.availableHeadroom, iso) + '.';
            String follow = 'Would you like to review the ' + nextYear.year + ' funding position and the '
                + 'Opportunities that could help fill it?';
            return lead + '\n\n' + follow;
        }

        // Searched the future horizon and found no year with room.
        String span;
        if (nextYear != null && !nextYear.yearsChecked.isEmpty()) {
            String last = nextYear.yearsChecked[nextYear.yearsChecked.size() - 1];
            span = (a.fiscalYear != null && last != a.fiscalYear)
                ? name + ' has no available Headroom from ' + a.fiscalYear + ' through ' + last + '.'
                : state;
        } else {
            span = state;
        }
        String alt = 'Would you like to check ' + a.category + ' in other countries or explore other '
            + 'programs in ' + a.country + ' that may need funding?';
        return span + '\n\n' + alt;
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
            // No available Headroom (overfunded or fully funded): steer to alternatives, objectively.
            return 'Would you like to check ' + a.category + ' in other countries, or explore other programs in '
                + a.country + ' that may have available Headroom?';
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
            interp = 'This program is overfunded on secured funding by '
                + AmaizeFormat.money(-a.securedHeadroom, iso) + ' across ' + a.budgetLinesIncluded
                + ' budget line' + (a.budgetLinesIncluded == 1 ? '' : 's') + '.';
        } else if (a.headroomStatus == 'Headroom Available') {
            interp = 'There is ' + AmaizeFormat.money(a.securedHeadroom, iso)
                + ' of available Headroom to raise against; on a forecast basis, after likely and pipeline funding, it is '
                + AmaizeFormat.money(a.forecastHeadroom, iso) + '.';
        } else {
            interp = 'Available Headroom is tight at ' + AmaizeFormat.money(a.securedHeadroom, iso)
                + '; confirm with Grants Finance before pitching. On a forecast basis it is '
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
