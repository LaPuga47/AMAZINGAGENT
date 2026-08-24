/**
 * AmaizeGetOpportunityContext — reads the key details of a grant (Opportunity)
 * by its name so the Headroom Check can run off the record the RM is looking at.
 *
 * In plain terms: the RM is on an Opportunity record and asks "check the headroom
 * for this grant." This action looks up that grant by name and hands back the
 * (country, program) target the headroom check should run against, plus the year.
 *
 * Where the COUNTRY and PROGRAM come from: One Acre Fund records a grant's
 * eligibility on its Restrictions, reached from the grant via its Gift Commitment
 * (Opportunity <- GiftCommitment <- Restriction__c). EACH Restriction pairs a
 * COUNTRY (Restriction_Country__c) with a PROGRAM / business unit
 * (Business_Unit__c). We source BOTH from there — the program is NOT taken from
 * Opportunity.Theme_Tag__c, whose values ("Carbon", "Agroforestry/Tree") were never
 * One Acre Fund business units and so never matched the budget data.
 *
 * Business_Unit__c uses the SAME restricted-picklist domain as
 * Budget_Line__c.BusinessUnit__c — base names ("Core Program") and country-suffixed
 * variants ("Core Program - KE") — so it maps directly onto what check_headroom
 * matches against.
 *
 * A grant can carry restrictions spanning several countries or programs, or only
 * non-specific sentinels ("Global" / "No Country Restriction" for country;
 * "No Purpose Restriction" / "N/A" for program). Because headroom is computed per
 * (country, program), we only pass a target straight through when exactly ONE
 * specific country AND ONE specific program apply; otherwise we hand back the
 * choices and let the RM pick.
 *
 * The LLM quotes the grant NAME from the conversation; Apex resolves the record
 * (per the platform rule that the model passes names, not record Ids). Read-only.
 */
public with sharing class AmaizeGetOpportunityContext {

    // Restriction_Country__c values that do NOT pin a grant to a single country's budget.
    private static final Set<String> NON_COUNTRY = new Set<String>{
        'global', 'no country restriction'
    };

    // Business_Unit__c values that do NOT pin a grant to a specific program.
    private static final Set<String> NON_PROGRAM = new Set<String>{
        'no purpose restriction', 'n/a'
    };

    /* ---------------- Action input ---------------- */
    public class Request {
        @InvocableVariable(
            label='Opportunity Name'
            description='The name (or part of the name) of the grant/opportunity to read'
            required=true)
        public String opportunityName;
    }

    /* ---------------- Action output ---------------- */
    public class Result {
        @InvocableVariable(
            label='Summary'
            description='Human-readable summary of the grant context')
        public String summary;

        @InvocableVariable(label='Country' description='Eligible country from the grant\'s restriction (set only when a single specific country applies)')
        public String country;

        @InvocableVariable(label='Program' description='Program / business unit from the grant\'s restriction, matched to Budget_Line__c.BusinessUnit__c (set only when a single specific program applies)')
        public String program;

        @InvocableVariable(label='Year' description='Budget year derived from the close date')
        public Integer year;

        @InvocableVariable(label='Found' description='True if exactly one matching grant resolves to a single specific country AND program')
        public Boolean found;
    }

    @InvocableMethod(
        label='Get Opportunity Context'
        description='Reads the eligible country, program, and year from a grant/opportunity by name so the headroom check can use them.')
    public static List<Result> getContext(List<Request> requests) {
        List<Result> results = new List<Result>();

        // Load, in ONE query, every restriction whose grant name matches ANY request's
        // words. This bounds the candidate set instead of pulling thousands of grants.
        List<Restriction__c> restrs = loadCandidates(requests);

        // Group once: grant -> its record, and grant -> the DISTINCT set of eligible
        // (country, program) pairs, with each sentinel element reduced to null.
        Map<Id, Opportunity> oppById = new Map<Id, Opportunity>();
        Map<Id, List<CountryProgram>> pairsByOpp = new Map<Id, List<CountryProgram>>();
        Map<Id, Set<String>> seenPairs = new Map<Id, Set<String>>();
        for (Restriction__c rec : restrs) {
            if (rec.Gift_Commitment__r == null) { continue; }
            Opportunity o = rec.Gift_Commitment__r.Opportunity;
            if (o == null || o.Name == null) { continue; }
            oppById.put(o.Id, o);
            if (!pairsByOpp.containsKey(o.Id)) {
                pairsByOpp.put(o.Id, new List<CountryProgram>());
                seenPairs.put(o.Id, new Set<String>());
            }
            String c = specificOrNull(rec.Restriction_Country__c, NON_COUNTRY);
            String p = specificOrNull(rec.Business_Unit__c, NON_PROGRAM);
            // Dedupe on the (country, program) pair; "||" never appears in picklist text.
            String key = (c == null ? '' : c) + '||' + (p == null ? '' : p);
            if (seenPairs.get(o.Id).add(key)) {
                pairsByOpp.get(o.Id).add(new CountryProgram(c, p));
            }
        }

        for (Request req : requests) {
            results.add(answerOne(req, oppById, pairsByOpp));
        }
        return results;
    }

    /** A single eligible (country, program) pair; each element is null when it was a sentinel. */
    private class CountryProgram {
        String country;
        String program;
        CountryProgram(String country, String program) {
            this.country = country;
            this.program = program;
        }
    }

    /**
     * Load the candidate restrictions in a single query. We turn each request's grant name
     * into significant words and require the grant Name to contain all of them (one LIKE
     * per word), OR-ing the requests together. Tokens are alphanumeric-only (see
     * AmaizeMatch.significantTokens), so they embed safely in the LIKE clauses.
     */
    private static List<Restriction__c> loadCandidates(List<Request> requests) {
        List<String> orClauses = new List<String>();
        for (Request req : requests) {
            if (req == null || String.isBlank(req.opportunityName)) { continue; }
            List<String> toks = AmaizeMatch.significantTokens(req.opportunityName);
            if (toks.isEmpty()) { continue; }
            List<String> likes = new List<String>();
            for (String t : toks) {
                likes.add('Gift_Commitment__r.Opportunity.Name LIKE \'%' + t + '%\'');
            }
            orClauses.add('(' + String.join(likes, ' AND ') + ')');
        }
        if (orClauses.isEmpty()) {
            return new List<Restriction__c>();
        }

        String soql =
            'SELECT Restriction_Country__c, '
          + 'Business_Unit__c, '
          + 'Gift_Commitment__r.Opportunity.Id, '
          + 'Gift_Commitment__r.Opportunity.Name, '
          + 'Gift_Commitment__r.Opportunity.CloseDate, '
          + 'Gift_Commitment__r.Opportunity.Amount, '
          + 'Gift_Commitment__r.Opportunity.StageName, '
          + 'Gift_Commitment__r.Opportunity.Guardian__c '
          + 'FROM Restriction__c '
          + 'WHERE Gift_Commitment__r.OpportunityId != null '
          + 'AND Gift_Commitment__r.Opportunity.StageName != \'Closed Lost\' '
          + 'AND (' + String.join(orClauses, ' OR ') + ') '
          + 'LIMIT 2000';
        return Database.query(soql);
    }

    /** Resolve one named grant and return its context. */
    private static Result answerOne(Request req, Map<Id, Opportunity> oppById,
            Map<Id, List<CountryProgram>> pairsByOpp) {
        Result r = new Result();

        // Match by tokens, not by exact substring: the RM rarely types punctuation
        // like the en-dash in "Greenfield – Kenya Core Program 2027". We keep a grant
        // if every significant word the RM typed appears somewhere in the grant name.
        List<Opportunity> hits = AmaizeMatch.tokenMatch(req.opportunityName, oppById.values());

        // No match: ask rather than guess.
        if (hits.isEmpty()) {
            r.found = false;
            r.summary = 'I couldn\'t find a grant matching "' + req.opportunityName
                + '". Could you give me the exact opportunity name, or the country and program directly?';
            return r;
        }

        // More than one grant with that name: ask the RM to disambiguate (don't pick blindly).
        if (hits.size() > 1) {
            r.found = false;
            List<String> names = new List<String>();
            for (Opportunity o : hits) { names.add(o.Name); }
            r.summary = 'I found more than one grant matching "' + req.opportunityName
                + '":\n  • ' + String.join(names, '\n  • ')
                + '\nWhich one did you mean?';
            return r;
        }

        // Exactly one grant. Year is grant-level and unambiguous, so return it regardless
        // of how the (country, program) target resolves below.
        Opportunity o = hits[0];
        r.year = (o.CloseDate != null) ? o.CloseDate.year() : null;

        // The DISTINCT set of specific (country, program) pairs the grant is eligible for.
        List<CountryProgram> pairs = pairsByOpp.get(o.Id);
        if (pairs == null) { pairs = new List<CountryProgram>(); }
        List<String> countries = distinctSpecific(pairs, true);
        List<String> programs = distinctSpecific(pairs, false);

        // Rule 2e: no specific country at all — the grant is Global / not country-restricted.
        if (countries.isEmpty()) {
            r.found = false;
            r.summary = 'The grant "' + o.Name + '" isn\'t restricted to a specific country'
                + ' (it\'s marked Global or "No Country Restriction"), so headroom depends on where the money would go. '
                + 'Which country\'s headroom should I check?';
            return r;
        }

        // Rule 2d: several specific countries — list the country → program options, ask which.
        if (countries.size() > 1) {
            r.found = false;
            r.summary = 'The grant "' + o.Name + '" is eligible in more than one country:\n  • '
                + String.join(countryProgramOptions(pairs), '\n  • ')
                + '\nWhich country\'s headroom should I check?';
            return r;
        }

        // Exactly one specific country from here on — hand it back even when the program
        // still needs picking, so the agent can proceed once it's settled.
        String theCountry = countries[0];
        r.country = theCountry;

        // Rule 2c: one country, NO specific program — ask which program (or offer a scan).
        if (programs.isEmpty()) {
            r.found = false;
            r.summary = 'The grant "' + o.Name + '" is eligible in ' + theCountry
                + ' but carries no specific program restriction, so headroom depends on which program the money supports. '
                + 'Which program\'s headroom should I check? I can also scan all of ' + theCountry + '\'s programs instead.';
            return r;
        }

        // Rule 2b: one country, several programs — return the country, list the programs, ask which.
        if (programs.size() > 1) {
            programs.sort();
            r.found = false;
            r.summary = 'The grant "' + o.Name + '" (eligible in ' + theCountry
                + ') covers more than one program:\n  • '
                + String.join(programs, '\n  • ')
                + '\nWhich program\'s headroom should I check?';
            return r;
        }

        // Rule 2a: exactly one specific country AND one specific program — the happy path.
        r.found = true;
        r.program = programs[0];
        r.summary = 'Grant "' + o.Name + '": country ' + theCountry
            + ', program ' + r.program
            + ', stage ' + o.StageName
            + ', amount ' + AmaizeFormat.money(o.Amount)
            + (String.isNotBlank(o.Guardian__c) ? ', RM ' + o.Guardian__c : '') + '.';
        return r;
    }

    /** Reduce a restriction value to null when it's blank or a known non-specific sentinel. */
    private static String specificOrNull(String value, Set<String> sentinels) {
        if (String.isBlank(value)) { return null; }
        if (sentinels.contains(value.trim().toLowerCase())) { return null; }
        return value.trim();
    }

    /**
     * The distinct specific country (wantCountry=true) or program (wantCountry=false) values
     * across the grant's (country, program) pairs. Sentinels were already dropped to null.
     */
    private static List<String> distinctSpecific(List<CountryProgram> pairs, Boolean wantCountry) {
        Set<String> seen = new Set<String>();
        List<String> out = new List<String>();
        for (CountryProgram cp : pairs) {
            String v = wantCountry ? cp.country : cp.program;
            if (v == null) { continue; }
            if (seen.add(v)) { out.add(v); }
        }
        return out;
    }

    /**
     * For the multi-country case: the distinct "Country → Program" option lines a grant
     * offers, so the RM can see which program pairs with each eligible country.
     */
    private static List<String> countryProgramOptions(List<CountryProgram> pairs) {
        Set<String> seen = new Set<String>();
        List<String> out = new List<String>();
        for (CountryProgram cp : pairs) {
            if (cp.country == null) { continue; }
            String line = cp.country + ' → ' + (cp.program == null ? '(no specific program)' : cp.program);
            if (seen.add(line)) { out.add(line); }
        }
        out.sort();
        return out;
    }
}