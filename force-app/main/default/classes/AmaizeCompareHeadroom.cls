/**
 * AmaizeCompareHeadroom — concise multi-group Headroom comparison for the Headroom Analysis
 * subagent. Given a governed category/program and several countries (+ optional fiscal year),
 * it resolves EACH country independently through the SAME governed engine
 * (HeadroomService.aggregate), then returns ONE concise comparison — a lead interpretation,
 * one compact line per country, and a group-level summary — instead of a full financial block
 * per country. Full detail stays available via analyze_headroom drill-down.
 *
 * Financial interpretation is explicit and correct: a negative Forecast Headroom is shown as a
 * positive-magnitude "Funding Gap"; a positive one as "Available Headroom". Consistency is
 * guaranteed — each line's value comes from the identical governed aggregation a direct query
 * uses. Read-only. Scalar I/O.
 */
public with sharing class AmaizeCompareHeadroom {

    private static final Integer MAX_GROUPS = 8;

    public class Request {
        @InvocableVariable(label='Program' description='Governed Headroom category / program, e.g. Core Program, Rural Retail, Trees.' required=true)
        public String program;
        @InvocableVariable(label='Countries' description='The countries to compare, comma- or semicolon-separated, e.g. "Malawi, Kenya, Rwanda, Burundi".' required=true)
        public String countries;
        @InvocableVariable(label='Fiscal Year' description='Fiscal year, e.g. 2027. Defaults to the current scenario when omitted.' required=false)
        public Integer fiscalYear;
    }

    public class Result {
        @InvocableVariable(label='Summary' description='Concise multi-country Headroom comparison to show the user.')
        public String summary;
        @InvocableVariable(label='Match Count' description='How many country groups were compared.')
        public Integer matchCount;
        @InvocableVariable(label='Results JSON' description='Machine-readable per-country governed aggregation.')
        public String resultsJson;
    }

    @InvocableMethod(
        label='Compare Headroom Across Groups'
        description='Compares governed Headroom across several countries for one program and fiscal year, returning a concise one-line-per-country funding-gap / available-headroom comparison with a group summary.')
    public static List<Result> compare(List<Request> requests) {
        List<Result> results = new List<Result>();
        HeadroomService service = new HeadroomService();
        for (Request req : requests) {
            results.add(answerOne(req, service));
        }
        return results;
    }

    private static Result answerOne(Request req, HeadroomService service) {
        Result r = new Result();
        String fy = (req.fiscalYear != null) ? String.valueOf(req.fiscalYear) : null;

        List<String> countries = parseCountries(req.countries);
        if (String.isBlank(req.program) || countries.isEmpty()) {
            r.matchCount = 0;
            r.summary = 'To compare, I need a program and at least two countries (e.g. "Core Program across Malawi, Kenya, Rwanda, Burundi").';
            r.resultsJson = '{"status":"NEEDS_INFO"}';
            return r;
        }

        // Resolve each country independently through the governed engine.
        List<HeadroomAggregate> groups = new List<HeadroomAggregate>();
        for (String c : countries) {
            groups.add(service.aggregate(req.program, c, fy));
        }

        // If the category itself isn't configured, that's the same for every country.
        if (groups[0].state == HeadroomAggregate.State.NOT_CONFIGURED) {
            r.matchCount = 0;
            r.summary = 'The Headroom aggregation rule for "' + groups[0].category
                + '" has not yet been configured, so I can\'t compare it across countries.';
            r.resultsJson = '{"status":"NOT_CONFIGURED"}';
            return r;
        }

        r.matchCount = groups.size();
        r.resultsJson = buildJson(groups);
        r.summary = compose(req, groups, fy);
        return r;
    }

    private static String compose(Request req, List<HeadroomAggregate> groups, String fy) {
        String category = groups[0].category;
        String fyText = (fy != null) ? fy
            : (groups[0].fiscalYear != null ? groups[0].fiscalYear : 'the current scenario');
        String iso = firstCurrency(groups);

        // Rank by biggest funding gap first (most negative forecast headroom); cap at 8.
        List<HeadroomAggregate> ordered = new List<HeadroomAggregate>(groups);
        ordered.sort(new ByGapDesc());
        Boolean capped = ordered.size() > MAX_GROUPS;
        if (capped) {
            List<HeadroomAggregate> top = new List<HeadroomAggregate>();
            for (Integer i = 0; i < MAX_GROUPS; i++) { top.add(ordered[i]); }
            ordered = top;
        }

        // Lead interpretation.
        Integer gaps = 0, capacity = 0, found = 0;
        for (HeadroomAggregate a : ordered) {
            if (a.state != HeadroomAggregate.State.FOUND) { continue; }
            found++;
            if (a.forecastHeadroom > 0) { gaps++; }
            else if (a.forecastHeadroom < 0) { capacity++; }
        }
        String lead;
        if (found == 0) {
            lead = 'For ' + category + ' in ' + fyText + ', no qualifying Budget Lines were found for the requested countries.';
        } else if (gaps > 0 && capacity == 0) {
            lead = 'For ' + category + ' in ' + fyText + ', all ' + found + ' countries currently show a funding gap (based on Forecast Headroom).';
        } else if (capacity > 0 && gaps == 0) {
            lead = 'For ' + category + ' in ' + fyText + ', all ' + found + ' countries are currently over-allocated (based on Forecast Headroom).';
        } else {
            lead = 'For ' + category + ' in ' + fyText + ', the countries show a mix of funding gaps and over-allocation (based on Forecast Headroom).';
        }

        // One compact line per country.
        List<String> lines = new List<String>();
        for (HeadroomAggregate a : ordered) {
            lines.add(line(a, iso));
        }

        // Group-level summary (only comparisons supported by the values).
        String summaryLine = groupSummary(ordered);

        // Budget scenario data-quality note (only if the scenario year differs from the lines' FY).
        String note = scenarioNote(groups, fy);

        String out = lead + '\n\n' + String.join(lines, '\n');
        if (summaryLine != null) { out += '\n\n' + summaryLine; }
        if (capped) { out += '\n\n_(Showing the 8 largest funding gaps of ' + groups.size() + ' countries.)_'; }
        if (note != null) { out += '\n\n' + note; }
        out += '\n\nWould you like the detailed breakdown for any one country?';
        return out;
    }

    private static String line(HeadroomAggregate a, String iso) {
        if (a.state == HeadroomAggregate.State.NONE) {
            return a.country + ': No qualifying Budget Line records found.';
        }
        if (a.state == HeadroomAggregate.State.ZERO) {
            return a.country + ': Not applicable (zero-Headroom category).';
        }
        if (a.state != HeadroomAggregate.State.FOUND) {
            return a.country + ': unavailable.';
        }
        // Org convention (mirrors the single-country response): positive Forecast Headroom =
        // unfunded need = a Funding Gap (also the headroom available to raise against);
        // negative = funded beyond budget = Over-allocated; zero = fully funded.
        String pos;
        if (a.forecastHeadroom > 0) {
            pos = 'Funding Gap ' + AmaizeFormat.money(a.forecastHeadroom, iso);
        } else if (a.forecastHeadroom < 0) {
            pos = 'Over-allocated ' + AmaizeFormat.money(-a.forecastHeadroom, iso);
        } else {
            pos = 'Fully funded (no gap)';
        }
        return a.country + ': ' + pos
            + ' | Secured ' + AmaizeFormat.money(a.securedFunding, iso)
            + ' | Pipeline ' + AmaizeFormat.money(a.pipelineFunding, iso);
    }

    private static String groupSummary(List<HeadroomAggregate> groups) {
        HeadroomAggregate biggestGap, mostCapacity;
        for (HeadroomAggregate a : groups) {
            if (a.state != HeadroomAggregate.State.FOUND) { continue; }
            // Positive forecast headroom = funding gap; the largest gap is the MOST positive.
            if (biggestGap == null || a.forecastHeadroom > biggestGap.forecastHeadroom) { biggestGap = a; }
            // Negative = available/over-funded; the most available is the MOST negative.
            if (mostCapacity == null || a.forecastHeadroom < mostCapacity.forecastHeadroom) { mostCapacity = a; }
        }
        if (biggestGap == null) { return null; }
        List<String> parts = new List<String>();
        if (biggestGap.forecastHeadroom > 0) {
            parts.add(biggestGap.country + ' has the largest funding gap');
        }
        if (mostCapacity.forecastHeadroom < 0 && mostCapacity != biggestGap) {
            parts.add(mostCapacity.country + ' is the most over-allocated');
        }
        return parts.isEmpty() ? null : capitalize(String.join(parts, ', ')) + '.';
    }

    private static String scenarioNote(List<HeadroomAggregate> groups, String fy) {
        for (HeadroomAggregate a : groups) {
            if (a.state == HeadroomAggregate.State.FOUND && a.scenarioLabel != null
                    && fy != null && !a.scenarioLabel.contains(fy)) {
                return '_Note: figures are for ' + fy + ' Budget Lines under the current "'
                    + a.scenarioLabel + '" scenario._';
            }
        }
        return null;
    }

    private static List<String> parseCountries(String raw) {
        List<String> out = new List<String>();
        if (String.isBlank(raw)) { return out; }
        Set<String> seen = new Set<String>();
        for (String part : raw.replace(';', ',').replace(' and ', ',').split(',')) {
            String c = part.trim();
            if (c != '' && seen.add(c.toLowerCase())) { out.add(c); }
        }
        return out;
    }

    private static String firstCurrency(List<HeadroomAggregate> groups) {
        for (HeadroomAggregate a : groups) { if (a.currencyIsoCode != null) { return a.currencyIsoCode; } }
        return null;
    }

    private static String capitalize(String s) {
        return String.isBlank(s) ? s : s.substring(0,1).toUpperCase() + s.substring(1);
    }

    private class ByGapDesc implements Comparator<HeadroomAggregate> {
        public Integer compare(HeadroomAggregate a, HeadroomAggregate b) {
            // FOUND groups first, then by most negative forecast headroom (biggest gap) first.
            Boolean af = a.state == HeadroomAggregate.State.FOUND;
            Boolean bf = b.state == HeadroomAggregate.State.FOUND;
            if (af != bf) { return af ? -1 : 1; }
            if (!af) { return 0; }
            if (a.forecastHeadroom == b.forecastHeadroom) { return 0; }
            // Biggest funding gap (most positive forecast headroom) first.
            return (a.forecastHeadroom > b.forecastHeadroom) ? -1 : 1;
        }
    }

    private static String buildJson(List<HeadroomAggregate> groups) {
        List<Map<String, Object>> rows = new List<Map<String, Object>>();
        for (HeadroomAggregate a : groups) {
            rows.add(new Map<String, Object>{
                'country' => a.country, 'category' => a.category, 'fiscalYear' => a.fiscalYear,
                'state' => String.valueOf(a.state),
                'forecastHeadroom' => a.forecastHeadroom, 'securedHeadroom' => a.securedHeadroom,
                'fundingGap' => (a.forecastHeadroom > 0 ? a.forecastHeadroom : 0),
                'securedFunding' => a.securedFunding, 'pipelineFunding' => a.pipelineFunding,
                'budgetAmount' => a.budgetAmount, 'headroomStatus' => a.headroomStatus,
                'budgetLinesIncluded' => a.budgetLinesIncluded
            });
        }
        return JSON.serialize(rows);
    }
}
