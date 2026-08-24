/**
 * AmaizeSearchSimilarGrants — the "Idea & Research" action (Step 1).
 *
 * In plain terms: before an RM creates a brand-new grant, this finds the grants
 * One Acre Fund already has for the same country and program/theme, so the RM can
 * see what exists and decide whether to start fresh or join an existing effort.
 *
 * It returns the matches (name, stage, amount, RM, close date) plus a suggestion
 * on whether to create a new opportunity or associate with an existing one.
 * Read-only — it never changes data.
 */
public with sharing class AmaizeSearchSimilarGrants {

    /* ---------------- Action input ---------------- */
    public class Request {
        @InvocableVariable(
            label='Country'
            description='Country to search, e.g. Kenya'
            required=true)
        public String country;

        @InvocableVariable(
            label='Theme'
            description='Program / theme to search, e.g. Core Program or Carbon'
            required=true)
        public String theme;
    }

    /* ---------------- Action output ---------------- */
    public class Result {
        @InvocableVariable(
            label='Summary'
            description='Human-readable list of matching grants and a suggested next step')
        public String summary;

        @InvocableVariable(
            label='Match Count'
            description='How many existing grants matched')
        public Integer matchCount;

        @InvocableVariable(
            label='Results JSON'
            description='Machine-readable list of matching grants')
        public String resultsJson;
    }

    @InvocableMethod(
        label='Search Similar Grants'
        description='Finds existing grants for the same country and theme, and suggests whether to create new or associate with an existing one.')
    public static List<Result> search(List<Request> requests) {
        List<Result> results = new List<Result>();

        // Collect all requested countries so we can query once (no SOQL in a loop).
        Set<String> countries = new Set<String>();
        for (Request req : requests) {
            if (req.country != null) countries.add(req.country.trim());
        }

        // Pull every non-lost grant in those countries in a single query, biggest first.
        // We refine the theme match in memory because Theme_Tag__c is a multi-select.
        List<Opportunity> allOpps = countries.isEmpty()
            ? new List<Opportunity>()
            : [SELECT Name, StageName, Amount, Probability, CloseDate,
                      Country_Tag__c, Theme_Tag__c, Guardian__c
               FROM Opportunity
               WHERE Country_Tag__c IN :countries AND StageName != 'Closed Lost'
               ORDER BY Amount DESC
               LIMIT 200];

        for (Request req : requests) {
            results.add(answerOne(req, allOpps));
        }
        return results;
    }

    /** Build the answer for one search request from the pre-loaded grants. */
    private static Result answerOne(Request req, List<Opportunity> allOpps) {
        Result r = new Result();
        List<Opportunity> matches = new List<Opportunity>();

        // Keep only grants in the same country whose theme tag contains the requested theme.
        for (Opportunity o : allOpps) {
            Boolean sameCountry = o.Country_Tag__c != null && req.country != null
                && o.Country_Tag__c.equalsIgnoreCase(req.country.trim());
            Boolean sameTheme = o.Theme_Tag__c != null && req.theme != null
                && o.Theme_Tag__c.containsIgnoreCase(req.theme.trim());
            if (sameCountry && sameTheme) {
                matches.add(o);
            }
        }

        r.matchCount = matches.size();

        // No matches: tell the RM there's nothing yet and suggest creating a new grant,
        // then offer the natural next step (check whether there's even room to raise here).
        if (matches.isEmpty()) {
            r.summary = 'I found no existing grants for ' + req.theme + ' in ' + req.country
                + '. This looks like a new area — you can create a new opportunity for it. '
                + 'Want me to check the funding headroom for ' + req.theme + ' in ' + req.country
                + ' first, so you know whether there\'s room to raise?';
            r.resultsJson = '[]';
            return r;
        }

        // Build the list the RM sees as Markdown bullets (the Agentforce panel renders
        // Markdown), plus a machine-readable copy. We **bold** the grant name and put each
        // grant on its own "- " line so the list doesn't collapse into a wall of text.
        List<String> lines = new List<String>();
        List<Map<String, Object>> jsonRows = new List<Map<String, Object>>();
        for (Opportunity o : matches) {
            lines.add('- **' + o.Name + '** — ' + o.StageName + ', ' + AmaizeFormat.money(o.Amount)
                + (o.Probability != null ? ' at ' + String.valueOf(Integer.valueOf(o.Probability)) + '%' : '')
                + (String.isNotBlank(o.Guardian__c) ? ', RM ' + o.Guardian__c : '')
                + (o.CloseDate != null ? ', closes ' + o.CloseDate.format() : ''));
            jsonRows.add(new Map<String, Object>{
                'name' => o.Name, 'stage' => o.StageName, 'amount' => o.Amount,
                'probability' => o.Probability, 'guardian' => o.Guardian__c,
                'closeDate' => (o.CloseDate != null ? String.valueOf(o.CloseDate) : null)
            });
        }
        r.resultsJson = JSON.serialize(jsonRows);

        // Suggest next step: if anything is already in flight, lean toward associating, and
        // offer the obvious follow-up — a headroom check before pitching anything new here.
        String suggestion = '\n\n**Suggestion:** There '
            + (matches.size() == 1 ? 'is already 1 grant' : 'are already ' + matches.size() + ' grants')
            + ' for this country and theme. Consider associating your new donor with an existing effort '
            + 'rather than creating a duplicate — or create a new opportunity if this is a genuinely separate ask. '
            + 'Want me to check the funding headroom for ' + req.theme + ' in ' + req.country
            + ' before you pitch?';

        // header  <blank>  bulleted list  (suggestion already starts with its own blank line)
        r.summary = '**Found ' + matches.size() + ' existing grant'
            + (matches.size() == 1 ? '' : 's') + ' for ' + req.theme + ' in ' + req.country + ':**\n\n'
            + String.join(lines, '\n') + suggestion;
        return r;
    }
}