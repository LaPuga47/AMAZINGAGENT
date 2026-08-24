/**
 * AmaizeFindPrograms — scans the WHOLE current budget scenario to answer
 * portfolio questions.
 *
 * In plain terms: this answers questions like "which programs are over-funded?",
 * "where do we have the most room to raise?", or "show me the tight ones in Kenya."
 * Where AmaizeCheckHeadroom looks at ONE country+program, this scans every
 * Budget_Line__c in the current scenario, aggregated by (country, business unit,
 * fiscal year), computes each group's status using the shared AmaizeBudgetHeadroom
 * rule, keeps the ones that match what the user asked for, and returns them sorted
 * current-year-first then by how big the gap or surplus is.
 *
 * Read-only. Scalar I/O (a human summary, a count, and a JSON list).
 */
public with sharing class AmaizeFindPrograms {

    // Cap how many rows we list back so a huge match set stays readable in chat.
    private static final Integer MAX_RESULTS = 15;

    /* ---------------- Action input ---------------- */
    public class Request {
        @InvocableVariable(
            label='Status Filter'
            description='Which programs to find: "over-funded" (or "red"/"surplus"), "room"/"green"/"gap" (room to pitch), "tight"/"amber", or "all".'
            required=true)
        public String statusFilter;

        @InvocableVariable(
            label='Country'
            description='Optional: limit to one country, e.g. Kenya. Leave blank for all countries.'
            required=false)
        public String country;

        @InvocableVariable(
            label='Year'
            description='Optional: limit to one fiscal year, e.g. 2027. Leave blank for all years.'
            required=false)
        public Integer year;
    }

    /* ---------------- Action output ---------------- */
    public class Result {
        @InvocableVariable(
            label='Summary'
            description='Human-readable list of the matching programs to show the user.')
        public String summary;

        @InvocableVariable(
            label='Match Count'
            description='How many programs matched the filter.')
        public Integer matchCount;

        @InvocableVariable(
            label='Results JSON'
            description='Machine-readable list of matching programs.')
        public String resultsJson;
    }

    @InvocableMethod(
        label='Find Programs by Headroom Status'
        description='Scans the current budget scenario and returns programs that are over-funded, have room to pitch, or are tight. Use for portfolio questions like "which programs are over-funded?"')
    public static List<Result> find(List<Request> requests) {
        List<Result> results = new List<Result>();

        // The current scenario anchors "current + next year first" ordering below.
        List<Budget_Scenario__c> currentScenarios = [
            SELECT Id, Fiscal_Year__c
            FROM Budget_Scenario__c
            WHERE Is_Current_Scenario__c = true
            LIMIT 1
        ];
        String currentFy = currentScenarios.isEmpty() ? null : currentScenarios[0].Fiscal_Year__c;
        String nextFy = null;
        if (currentFy != null && currentFy.isNumeric()) {
            nextFy = String.valueOf(Integer.valueOf(currentFy) + 1);
        }

        // Load the whole current scenario, aggregated once (no SOQL in a loop). The
        // budget file is small (well under a couple hundred groups), so this comfortably
        // covers everything.
        List<AggregateResult> ars = [
            SELECT Country__c c, BusinessUnit__c bu, Fiscal_Year__c fy,
                   SUM(Budget_Amount__c) bud, SUM(Secured_Funding__c) sec, COUNT(Id) cnt
            FROM Budget_Line__c
            WHERE Budget_Scenario__r.Is_Current_Scenario__c = true
            GROUP BY Country__c, BusinessUnit__c, Fiscal_Year__c
            LIMIT 2000
        ];

        for (Request req : requests) {
            results.add(answerOne(req, ars, currentFy, nextFy));
        }
        return results;
    }

    /** Answer one portfolio request from the pre-loaded aggregate groups. */
    private static Result answerOne(Request req, List<AggregateResult> ars, String currentFy, String nextFy) {
        Result r = new Result();

        // Normalise the requested status into one of our tri-state words (or "ALL").
        String wantStatus = normaliseStatus(req.statusFilter);

        // Build the matching list, capturing each group's status and its "magnitude"
        // (how far from zero the Secured headroom is) for sorting.
        List<Map<String, Object>> matches = new List<Map<String, Object>>();
        for (AggregateResult ar : ars) {
            String country = (String) ar.get('c');
            String bu = (String) ar.get('bu');
            String fy = (String) ar.get('fy');

            // Optional country / year filters.
            if (String.isNotBlank(req.country)
                && (country == null || !country.equalsIgnoreCase(req.country.trim()))) {
                continue;
            }
            if (req.year != null && (fy == null || fy != String.valueOf(req.year))) {
                continue;
            }

            Decimal securedHeadroom = AmaizeBudgetHeadroom.securedHeadroom(
                (Decimal) ar.get('bud'), (Decimal) ar.get('sec'));
            String status = AmaizeBudgetHeadroom.statusFor(securedHeadroom);

            // Keep only groups matching the requested status (or everything if "ALL").
            if (wantStatus != 'ALL' && status != wantStatus) {
                continue;
            }

            // Order bucket: current fiscal year first, then next fiscal year, then everything else.
            Integer yearRank = 2;
            if (fy != null && fy == currentFy) { yearRank = 0; }
            else if (fy != null && fy == nextFy) { yearRank = 1; }

            matches.add(new Map<String, Object>{
                'country' => country, 'program' => bu, 'year' => fy,
                'status' => status, 'securedHeadroom' => securedHeadroom,
                'magnitude' => Math.abs(securedHeadroom), 'yearRank' => yearRank
            });
        }

        // Sort current+next fiscal year first, then by magnitude descending (biggest
        // surplus / biggest gap first) within each bucket.
        matches.sort(new ByYearThenMagnitudeDesc());

        r.matchCount = matches.size();
        r.resultsJson = JSON.serialize(matches);
        r.summary = buildSummary(wantStatus, req, matches);
        return r;
    }

    /** Turn a free-text status into the tri-state vocabulary or "ALL". */
    private static String normaliseStatus(String raw) {
        String s = (raw == null) ? '' : raw.toLowerCase();
        if (s.contains('over') || s.contains('red') || s.contains('surplus') || s.contains('fully fund')) {
            return 'Headroom Unavailable';
        }
        if (s.contains('green') || s.contains('room') || s.contains('gap') || s.contains('pitch') || s.contains('under')) {
            return 'Headroom Available';
        }
        if (s.contains('amber') || s.contains('tight') || s.contains('caution') || s.contains('mixed')) {
            return 'Some Headroom Available';
        }
        if (s.contains('all') || String.isBlank(s)) {
            return 'ALL';
        }
        // Default: if we can't tell, treat as "over-funded" since that's the common ask.
        return 'Headroom Unavailable';
    }

    /** Compose the human-readable list, scoped by any country/year filter. */
    private static String buildSummary(String wantStatus, Request req, List<Map<String, Object>> matches) {
        // A friendly label for the status being reported. Phrased to read naturally
        // after "...programs that " (e.g. "programs that are over-funded").
        Map<String, String> label = new Map<String, String>{
            'Headroom Unavailable' => 'are over-funded',
            'Headroom Available' => 'have room to pitch',
            'Some Headroom Available' => 'are tight or mixed',
            'ALL' => 'are in the current budget'
        };
        String scope = '';
        if (String.isNotBlank(req.country)) scope += ' in ' + req.country;
        if (req.year != null) scope += ' for ' + req.year;

        if (matches.isEmpty()) {
            return 'I found no programs that ' + label.get(wantStatus) + scope + '.';
        }

        // Build the list as Markdown bullets. The Agentforce panel renders Markdown, so we
        // use "- " bullets (each on its own line) and **bold** the program name. A blank line
        // separates the header, the list, and the footer so they don't collapse together.
        Integer shown = Math.min(matches.size(), MAX_RESULTS);
        List<String> lines = new List<String>();
        for (Integer i = 0; i < shown; i++) {
            Map<String, Object> m = matches[i];
            Decimal hr = (Decimal) m.get('securedHeadroom');
            String hrText = (hr >= 0 ? AmaizeFormat.money(hr) + ' of room' : AmaizeFormat.money(hr) + ' surplus');
            lines.add('- **' + m.get('program') + ' — ' + m.get('country')
                + ' (' + m.get('year') + ')**: ' + hrText
                + (wantStatus == 'ALL' ? ' _(' + m.get('status') + ')_' : ''));
        }

        String header = '**Found ' + matches.size() + ' program'
            + (matches.size() == 1 ? '' : 's') + ' that ' + label.get(wantStatus) + scope + '.**'
            + (matches.size() > shown ? ' Showing the top ' + shown + ' by size:' : '');

        // Footers double as a contextual next-step offer, so the user always has an
        // obvious move after the list — not just a static label.
        String footer;
        if (wantStatus == 'Headroom Unavailable') {
            footer = 'These are over-funded — don\'t raise more here without Grants Finance approval. '
                + 'Want me to find programs that still need funding instead? Just say which country or theme.';
        } else if (wantStatus == 'Headroom Available') {
            footer = 'These have a genuine funding gap — good targets to pitch. '
                + 'Name any one and I\'ll pull its full headroom breakdown, or show the grants already in play there.';
        } else if (wantStatus == 'Some Headroom Available') {
            footer = 'These are close to balanced — check with Grants Finance before pitching. '
                + 'Want the full headroom detail on any of them? Just name the country and program.';
        } else {
            footer = 'Want the full headroom breakdown for any of these? Just name the country and program.';
        }

        // header  <blank>  bulleted list  <blank>  footer
        return header + '\n\n' + String.join(lines, '\n') + '\n\n' + footer;
    }

    /**
     * Comparator: current fiscal year first, then next fiscal year, then everything
     * else; within each bucket, sort by magnitude (distance from zero) descending.
     */
    private class ByYearThenMagnitudeDesc implements Comparator<Map<String, Object>> {
        public Integer compare(Map<String, Object> a, Map<String, Object> b) {
            Integer ya = (Integer) a.get('yearRank');
            Integer yb = (Integer) b.get('yearRank');
            if (ya != yb) { return (ya > yb) ? 1 : -1; }
            Decimal ma = (Decimal) a.get('magnitude');
            Decimal mb = (Decimal) b.get('magnitude');
            if (ma == mb) return 0;
            return (mb > ma) ? 1 : -1;
        }
    }
}