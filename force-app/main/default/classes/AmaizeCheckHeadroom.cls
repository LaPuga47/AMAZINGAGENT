/**
 * AmaizeCheckHeadroom — the primary "Headroom Check" action (Step 2).
 *
 * In plain terms: given a country, a program, and a year, this looks up One Acre
 * Fund's REAL budget data (Budget_Scenario__c / Budget_Line__c, current scenario
 * only) and works out whether there is still room to raise money there. "Secured
 * headroom" = how much the program costs to run minus how much restricted funding
 * is already secured — exactly the org's own Secured_Headroom__c / Headroom_status__c
 * formulas, computed here in Apex against the org's aggregate figures so the two
 * can never disagree. It decides a Headroom Available / Some Headroom Available /
 * Headroom Unavailable status, and — when things look tight or unavailable — also
 * names the biggest grant that is eating up the headroom so the RM can see why.
 *
 * A "program" (BusinessUnit__c) can be recorded as a base name (e.g. "Core Program")
 * or a country-suffixed variant (e.g. "Core Program - KE"); both are summed together
 * for a given country so the RM gets one combined answer regardless of which naming
 * pattern Finance used for that country.
 *
 * It NEVER changes any data. It only reads and explains.
 *
 * Outputs are all scalar (String) per Agentforce platform rules: a machine-readable
 * JSON string plus a ready-to-speak human summary and a short status word.
 */
public with sharing class AmaizeCheckHeadroom {

    /* ---------------- Action input ---------------- */
    public class Request {
        @InvocableVariable(
            label='Country'
            description='Country to check, e.g. Kenya or Rwanda'
            required=true)
        public String country;

        @InvocableVariable(
            label='Program'
            description='Program / business unit to check, e.g. Core Program or Carbon'
            required=true)
        public String program;

        @InvocableVariable(
            label='Year'
            description='Fiscal year to check, e.g. 2027. Defaults to the current budget scenario\'s year when omitted.'
            required=false)
        public Integer year;
    }

    /* ---------------- Action output ---------------- */
    public class Result {
        @InvocableVariable(
            label='Summary'
            description='Human-readable headroom summary and recommendation to show the user')
        public String summary;

        @InvocableVariable(
            label='Signal'
            description='Status: Headroom Available, Some Headroom Available, Headroom Unavailable, or UNKNOWN if no data')
        public String signal;

        @InvocableVariable(
            label='Headroom JSON'
            description='Machine-readable headroom detail for the requested country/program/year')
        public String headroomJson;

        @InvocableVariable(
            label='Found'
            description='True if a budget line was found for the requested combination')
        public Boolean found;
    }

    /**
     * Invocable entry point. Bulkified: accepts a list of requests and returns one
     * result per request, with all SOQL done up front outside the per-request loop.
     */
    @InvocableMethod(
        label='Check Funding Headroom'
        description='Looks up secured funding headroom for a country/program/year from the current budget scenario and returns a Go / Caution / Do-not-pitch recommendation with the reasoning.')
    public static List<Result> check(List<Request> requests) {
        List<Result> results = new List<Result>();

        // ---- Gather every country we were asked about, so we can load all matching
        //      budget-line groups in a single pair of queries (no SOQL in a loop). ----
        Set<String> countries = new Set<String>();
        for (Request req : requests) {
            if (String.isNotBlank(req.country)) {
                countries.add(req.country.trim());
            }
        }

        // The current scenario anchors the default fiscal year when a request omits
        // one, and also doubles as our "is there a current scenario at all" check.
        List<Budget_Scenario__c> currentScenarios = [
            SELECT Id, Fiscal_Year__c
            FROM Budget_Scenario__c
            WHERE Is_Current_Scenario__c = true
            LIMIT 1
        ];
        String currentFy = currentScenarios.isEmpty() ? null : currentScenarios[0].Fiscal_Year__c;

        // Load candidate budget-line GROUPS once, aggregated to (country, business unit,
        // fiscal year). We need TWO bounded slices so that, when a program is over-funded
        // or tight, we can suggest genuine ALTERNATIVES that need funding — without a slow
        // OR-join or a SOQL-in-a-loop:
        //   Query A — every group in the requested country/countries. Gives us the exact
        //             requested group(s) PLUS same-region siblings (other programs/years).
        //   Query B — every group in OTHER countries. Combined with the in-memory program
        //             match, this gives us same-theme alternatives elsewhere.
        // We merge both into one in-memory pool; matchAndSum() still resolves the exact
        // requested combination from it, and rankAlternatives() ranks the rest.
        List<AggregateResult> arsA = [
            SELECT Country__c c, BusinessUnit__c bu, Fiscal_Year__c fy,
                   SUM(Budget_Amount__c) bud, SUM(Secured_Funding__c) sec, COUNT(Id) cnt
            FROM Budget_Line__c
            WHERE Budget_Scenario__r.Is_Current_Scenario__c = true AND Country__c IN :countries
            GROUP BY Country__c, BusinessUnit__c, Fiscal_Year__c
            LIMIT 2000
        ];
        List<AggregateResult> arsB = [
            SELECT Country__c c, BusinessUnit__c bu, Fiscal_Year__c fy,
                   SUM(Budget_Amount__c) bud, SUM(Secured_Funding__c) sec, COUNT(Id) cnt
            FROM Budget_Line__c
            WHERE Budget_Scenario__r.Is_Current_Scenario__c = true AND Country__c NOT IN :countries
            GROUP BY Country__c, BusinessUnit__c, Fiscal_Year__c
            LIMIT 2000
        ];
        List<Grp> groups = toGroups(arsA);
        groups.addAll(toGroups(arsB));

        // Also load the grants already competing for headroom in these countries, so when
        // headroom is tight or unavailable we can name what is eating it. A grant's country
        // AND program both come from its Restriction (Restriction__c.Restriction_Country__c
        // and Restriction__c.Business_Unit__c, reached via GiftCommitment) — NOT the unused
        // Opportunity.Country_Tag__c or Opportunity.Theme_Tag__c. A grant can carry several
        // restrictions, so each (grant, country, business unit) is its own competing entry.
        // Closed Lost deals don't count as demand, so we exclude them.
        List<CompetingGrant> comps = new List<CompetingGrant>();
        if (!countries.isEmpty()) {
            Set<String> seen = new Set<String>();   // dedupe (grant + country + business unit)
            for (Restriction__c rec : [
                SELECT Restriction_Country__c,
                       Business_Unit__c,
                       Gift_Commitment__r.Opportunity.Id,
                       Gift_Commitment__r.Opportunity.Name,
                       Gift_Commitment__r.Opportunity.Amount,
                       Gift_Commitment__r.Opportunity.Probability,
                       Gift_Commitment__r.Opportunity.StageName,
                       Gift_Commitment__r.Opportunity.Guardian__c
                FROM Restriction__c
                WHERE Restriction_Country__c IN :countries
                  AND Gift_Commitment__r.OpportunityId != null
                  AND Gift_Commitment__r.Opportunity.StageName != 'Closed Lost'
                LIMIT 1000
            ]) {
                if (rec.Gift_Commitment__r == null) { continue; }
                Opportunity o = rec.Gift_Commitment__r.Opportunity;
                if (o == null) { continue; }
                String key = o.Id + '|' + rec.Restriction_Country__c + '|' + rec.Business_Unit__c;
                if (seen.contains(key)) { continue; }
                seen.add(key);
                CompetingGrant cg = new CompetingGrant();
                cg.country = rec.Restriction_Country__c;
                cg.businessUnit = rec.Business_Unit__c;
                cg.opp = o;
                comps.add(cg);
            }
        }

        // ---- Now answer each request from the data we already loaded. ----
        for (Request req : requests) {
            results.add(answerOne(req, groups, comps, currentFy));
        }
        return results;
    }

    /** A grant competing for headroom, paired with the specific country + program its restriction names. */
    private class CompetingGrant {
        String country;       // from Restriction__c.Restriction_Country__c
        String businessUnit;  // from Restriction__c.Business_Unit__c (the program)
        Opportunity opp;      // Name, Amount, Probability, StageName, Guardian__c
    }

    /** A budget-line group, aggregated by (country, business unit, fiscal year). */
    private class Grp {
        String country;
        String bu;
        String fy;
        Decimal bud;
        Decimal sec;
        Integer cnt;
        Decimal securedHeadroom;
        String status;
    }

    /** Convert raw aggregate rows into Grp wrappers, computing headroom/status once. */
    private static List<Grp> toGroups(List<AggregateResult> ars) {
        List<Grp> out = new List<Grp>();
        for (AggregateResult ar : ars) {
            Grp g = new Grp();
            g.country = (String) ar.get('c');
            g.bu = (String) ar.get('bu');
            g.fy = (String) ar.get('fy');
            g.bud = (Decimal) ar.get('bud');
            g.sec = (Decimal) ar.get('sec');
            g.cnt = (Integer) ar.get('cnt');
            g.securedHeadroom = AmaizeBudgetHeadroom.securedHeadroom(g.bud, g.sec);
            g.status = AmaizeBudgetHeadroom.statusFor(g.securedHeadroom);
            out.add(g);
        }
        return out;
    }

    /**
     * Build the answer for a single request from the pre-loaded groups.
     */
    private static Result answerOne(Request req, List<Grp> groups, List<CompetingGrant> comps, String currentFy) {
        Result r = new Result();

        String wantYear = req.year != null ? String.valueOf(req.year) : currentFy;
        Grp combined = matchAndSum(req, groups, wantYear);

        // No match? Be honest and ask — never invent numbers (brief guardrail).
        if (combined == null) {
            r.found = false;
            r.signal = 'UNKNOWN';
            r.summary = 'I don\'t have headroom data for ' + req.program + ' in ' + req.country
                + (wantYear != null ? ' for ' + wantYear : '')
                + '. I can only advise on combinations that exist in the current budget scenario. '
                + 'Please double-check the country and program, or ask Grants Finance to add this combination.';
            r.headroomJson = '{"found":false}';
            return r;
        }

        r.found = true;
        r.signal = combined.status;

        // Build the machine-readable JSON (kept internal; helps multi-turn follow-ups).
        Map<String, Object> j = new Map<String, Object>{
            'found' => true,
            'country' => combined.country,
            'program' => combined.bu,
            'year' => combined.fy,
            'budgetCost' => AmaizeBudgetHeadroom.budgetCost(combined.bud),
            'securedFunding' => AmaizeBudgetHeadroom.nz(combined.sec),
            'securedHeadroom' => combined.securedHeadroom,
            'lineCount' => combined.cnt,
            'signal' => combined.status
        };
        r.headroomJson = JSON.serialize(j);

        // Build the human-readable summary the agent will speak.
        r.summary = buildSummary(req, combined, comps, groups, wantYear);
        return r;
    }

    /**
     * Find every group matching this request's country + program (+ fiscal year), and
     * sum them into one combined figure. A "program" match is the business unit equal
     * to the requested program, OR the requested program with a " - <code>" country
     * suffix (e.g. "Core Program" matches "Core Program - KE") — Finance records some
     * programs with a base name and some with a country-suffixed variant, and both
     * should roll up into one answer for a given country.
     */
    private static Grp matchAndSum(Request req, List<Grp> groups, String wantYear) {
        String wantCountry = req.country == null ? '' : req.country.trim();
        String wantProgram = req.program == null ? '' : req.program.trim();

        Grp combined = null;
        for (Grp g : groups) {
            Boolean countryOk = wantCountry != '' && g.country != null && g.country.equalsIgnoreCase(wantCountry);
            Boolean programOk = programMatches(g.bu, wantProgram);
            Boolean yearOk = wantYear == null || (g.fy != null && g.fy == wantYear);
            if (!countryOk || !programOk || !yearOk) { continue; }

            if (combined == null) {
                combined = new Grp();
                combined.country = g.country;
                combined.bu = wantProgram;
                combined.fy = g.fy;
                combined.bud = 0;
                combined.sec = 0;
                combined.cnt = 0;
            }
            combined.bud += AmaizeBudgetHeadroom.nz(g.bud);
            combined.sec += AmaizeBudgetHeadroom.nz(g.sec);
            combined.cnt += g.cnt;
        }
        if (combined != null) {
            combined.securedHeadroom = AmaizeBudgetHeadroom.securedHeadroom(combined.bud, combined.sec);
            combined.status = AmaizeBudgetHeadroom.statusFor(combined.securedHeadroom);
        }
        return combined;
    }

    /**
     * Business-unit match. A program can be recorded either as a base name
     * ("Core Program") or as a country-suffixed variant ("Core Program - KE"); the
     * two forms name the same program and roll up together. We match when the values
     * are equal, OR when one is the other's " - <code>" suffixed variant — in EITHER
     * direction. The bidirectional check matters because the requested program can now
     * arrive as a suffixed value: Restriction__c.Business_Unit__c is a country-dependent
     * picklist whose specific values are the suffixed ones ("Core Program - KE"), while
     * the budget lines may be recorded under the base name ("Core Program"). Comparing
     * only the shared base name (the part before " - ") keeps distinct country variants
     * of the same program from cross-matching (e.g. "- KE" never matches "- RW").
     */
    private static Boolean programMatches(String bu, String program) {
        if (bu == null || String.isBlank(program)) { return false; }
        String buT = bu.trim();
        String pT = program.trim();
        if (buT.equalsIgnoreCase(pT)) { return true; }
        if (buT.toLowerCase().startsWith(pT.toLowerCase() + ' - ')) { return true; }
        return pT.toLowerCase().startsWith(buT.toLowerCase() + ' - ');
    }

    /**
     * Compose the spoken summary, leading with the Secured-headroom verdict, explaining
     * the "why", and — when tight or unavailable — listing the grant that is consuming
     * the headroom. Ends with a clear recommendation.
     */
    private static String buildSummary(Request req, Grp combined, List<CompetingGrant> comps,
            List<Grp> groups, String wantYear) {

        // A short, natural place reference, e.g. "Core Program in Kenya for 2027".
        String place = combined.bu + ' in ' + combined.country
            + (combined.fy != null ? ' for ' + combined.fy : '');

        Decimal budgetCost = AmaizeBudgetHeadroom.budgetCost(combined.bud);
        Decimal securedFunding = AmaizeBudgetHeadroom.nz(combined.sec);

        // The biggest grant in the same country+program — the deal that drives the
        // caution or that has already filled the budget. May be null for generated rows.
        Opportunity topDeal = topCompeting(combined.country, req.program, comps);

        String answer;         // the clear yes/no/limited + 1-2 lines of reasoning
        String recommendation; // a single path-forward line, after a blank line

        if (combined.status == 'Headroom Available') {
            // YES — there is room to raise.
            answer = '**Yes** — there\'s room to raise more for ' + place + '. '
                + 'You\'ve budgeted ' + AmaizeFormat.money(budgetCost)
                + ' and secured ' + AmaizeFormat.money(securedFunding)
                + ' so far, leaving about ' + AmaizeFormat.money(combined.securedHeadroom) + ' still to cover.';
            recommendation = '**Recommendation:** Go ahead and pitch — this is a strong target.';

        } else if (combined.status == 'Headroom Unavailable') {
            // NO — already fully funded (securedHeadroom is negative; surplus = -securedHeadroom).
            String because = topDeal != null
                ? ' — largely thanks to ' + funderLabel(topDeal) + '\'s '
                    + AmaizeFormat.money(topDeal.Amount)
                    + (topDeal.StageName == 'Closed Won' ? ' grant, which is already secured.' : ' deal in the pipeline.')
                : '.';
            answer = '**No** — ' + place + ' is already fully funded. '
                + 'Secured funding of ' + AmaizeFormat.money(securedFunding)
                + ' covers the ' + AmaizeFormat.money(budgetCost) + ' budget' + because;
            recommendation = '**Recommendation:** Hold off here and check with Grants Finance before raising anything more.';

        } else {
            // LIMITED — some room on paper, but it's tight.
            String risk = topDeal != null
                ? funderLabel(topDeal) + '\'s ' + AmaizeFormat.money(topDeal.Amount) + ' deal at '
                    + (topDeal.Probability == null ? '' : String.valueOf(Integer.valueOf(topDeal.Probability)) + '% ')
                    + 'would eat further into that room if it lands.'
                : 'expected pipeline demand would likely eat further into that room.';
            answer = '**Limited** — there\'s some room for ' + place + ', but it\'s tight. '
                + 'There\'s about ' + AmaizeFormat.money(combined.securedHeadroom) + ' of headroom on secured funding, but '
                + risk;
            recommendation = '**Recommendation:** Confirm with Grants Finance'
                + (topDeal != null && String.isNotBlank(topDeal.Guardian__c)
                    ? ' (and check the pipeline deal with ' + topDeal.Guardian__c + ')'
                    : '')
                + ' before pitching.';
        }

        // Build the base answer: verdict + reasoning, a blank line, the recommendation.
        String summary = answer + '\n\n' + recommendation;

        // ---- Proactive "think one step ahead" block, appended AFTER the recommendation. ----
        // Available: there's room, so point the user at the natural forward steps. The line
        // is deliberately FIGURE-FREE (no amounts, no new program names) — it only describes
        // actions the assistant can take next.
        if (combined.status == 'Headroom Available') {
            summary += '\n\n**Next:** I can pull the grants and funders already in play for '
                + place + ', or help you sketch a payment & reporting schedule once funding is secured. '
                + 'Just say the word.';

        } else {
            // Unavailable or Limited: there's no clear room here, so suggest OTHER programs
            // that genuinely need funding. These alternatives are computed in Apex from real
            // budget-line groups (never invented) and listed with their real figures.
            List<Grp> alts = rankAlternatives(req, combined, groups, wantYear);
            if (!alts.isEmpty()) {
                summary += '\n\n**Where to look instead — programs with real room to raise:**\n'
                    + altLines(req, combined, alts);
            } else {
                // Graceful fallback: nothing obvious nearby — offer the wider portfolio scan.
                summary += '\n\nI don\'t see other ' + req.program + ' programs or other '
                    + req.country + ' programs with clear room right now — '
                    + 'want me to scan the wider portfolio for the biggest funding gaps?';
            }
        }
        return summary;
    }

    /**
     * Rank up to three ALTERNATIVE programs that actually need funding (Headroom
     * Available), for when the requested program is unavailable or limited.
     *
     * "Same theme first" ordering (per the demo design): we lead with other programs
     * of the SAME theme (in any country), biggest room first, then fill any remaining
     * slots with SAME-COUNTRY programs of other themes, biggest room first. The exact
     * requested combination is always excluded.
     *
     * Every figure comes from the real budget-line groups; nothing is invented. We
     * reuse the shared AmaizeBudgetHeadroom rule so a follow-up check on any of these
     * would agree.
     */
    private static List<Grp> rankAlternatives(Request req, Grp combined, List<Grp> groups, String wantYear) {
        String wantCountry = req.country == null ? '' : req.country.trim();
        String wantProgram = req.program == null ? '' : req.program.trim();

        List<Grp> sameTheme = new List<Grp>();   // other countries, same theme
        List<Grp> sameCountry = new List<Grp>(); // same country, other themes

        for (Grp g : groups) {
            // Skip groups that are part of the exact requested combination.
            Boolean isRequested = g.country != null && g.country.equalsIgnoreCase(wantCountry)
                && programMatches(g.bu, wantProgram)
                && g.fy == wantYear;
            if (isRequested) { continue; }

            // Only suggest programs that clearly need funding.
            if (g.status != 'Headroom Available') { continue; }

            Boolean themeMatch = programMatches(g.bu, wantProgram);
            Boolean countryMatch = g.country != null && g.country.equalsIgnoreCase(wantCountry);
            if (themeMatch) {
                sameTheme.add(g);          // same theme, elsewhere — our preferred suggestion
            } else if (countryMatch) {
                sameCountry.add(g);        // same region, different theme — the fill-in
            }
            // (groups that are neither same-theme nor same-country can't appear: the two
            //  queries in check() only loaded same-country OR "all other countries" groups,
            //  and same-theme membership is checked above regardless of country.)
        }

        // Biggest secured room first within each group.
        sameTheme.sort(new ByHeadroomDesc());
        sameCountry.sort(new ByHeadroomDesc());

        // Same-theme leads; same-country fills the remaining slots, up to three total.
        List<Grp> ranked = new List<Grp>();
        ranked.addAll(sameTheme);
        ranked.addAll(sameCountry);
        if (ranked.size() > 3) {
            ranked = new List<Grp>{ ranked[0], ranked[1], ranked[2] };
        }
        return ranked;
    }

    /**
     * Render the alternatives as Markdown bullets with their real Secured headroom. A
     * group in the SAME country as the requested program (the "fill-in") is tagged
     * "(same region)" so the user can see why it's relevant.
     */
    private static String altLines(Request req, Grp combined, List<Grp> alts) {
        String wantCountry = req.country == null ? '' : req.country.trim();
        String wantProgram = req.program == null ? '' : req.program.trim();

        List<String> lines = new List<String>();
        for (Grp a : alts) {
            String yr = (a.fy == null) ? '' : ' (' + a.fy + ')';
            // Tag the same-country/other-theme fills; same-theme groups are the default suggestion.
            String tag = (!programMatches(a.bu, wantProgram)
                          && a.country != null && a.country.equalsIgnoreCase(wantCountry))
                ? ' _(same region)_' : '';
            lines.add('- **' + a.bu + ' — ' + a.country + yr + '**: '
                + AmaizeFormat.money(a.securedHeadroom) + ' of room' + tag);
        }
        return String.join(lines, '\n');
    }

    /**
     * Comparator: sort groups by Secured headroom DESCENDING, so the program with the
     * most room to raise comes first. Mirrors AmaizeFindPrograms.ByMagnitudeDesc.
     */
    private class ByHeadroomDesc implements Comparator<Grp> {
        public Integer compare(Grp a, Grp b) {
            if (a.securedHeadroom == b.securedHeadroom) { return 0; }
            return (b.securedHeadroom > a.securedHeadroom) ? 1 : -1;
        }
    }

    /**
     * Find the largest grant (by Amount) in the same country + program, excluding
     * Closed Lost. This is the deal that explains headroom being unavailable (already
     * covers the budget) or drives a "limited" caution (pipeline that would close the
     * remaining gap). Null if none.
     *
     * Both the grant's country and its program come from its Restriction (carried on the
     * paired CompetingGrant as Restriction_Country__c and Business_Unit__c). Program
     * matching reuses programMatches(), so a base business unit ("Core Program") also
     * matches its country-suffixed variant ("Core Program - KE") — mirroring how the
     * requested program is matched against the budget lines.
     */
    private static Opportunity topCompeting(String country, String program, List<CompetingGrant> comps) {
        Opportunity top = null;
        for (CompetingGrant c : comps) {
            Opportunity o = c.opp;
            Boolean sameCountry = c.country != null && country != null
                && c.country.equalsIgnoreCase(country);
            Boolean sameProgram = programMatches(c.businessUnit, program);
            if (sameCountry && sameProgram) {
                if (top == null || (o.Amount != null && o.Amount > AmaizeBudgetHeadroom.nz(top.Amount))) {
                    top = o;
                }
            }
        }
        return top;
    }

    /**
     * A short, readable funder reference from a grant name. Our grant names look like
     * "Continental Dev Bank – Kenya Carbon 2027-28", so we take the part before the dash
     * (the funder) for a natural phrase like "Continental Dev Bank's $2M deal".
     */
    private static String funderLabel(Opportunity o) {
        if (o == null || String.isBlank(o.Name)) {
            return 'an existing grant';
        }
        // Split on the en-dash or hyphen used in our grant names; keep the funder portion.
        List<String> parts = o.Name.split('[–-]', 2);
        return parts[0].trim();
    }
}