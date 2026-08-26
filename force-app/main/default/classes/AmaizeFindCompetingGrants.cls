/**
 * AmaizeFindCompetingGrants — the Competing Grants Analysis action.
 *
 * Given a funding scope (country + business unit, optionally narrowed by fiscal year and
 * the cost dimensions), it reports the grant Opportunities competing for that scope, the
 * combined competing pipeline versus remaining headroom, closing scenarios, and a severity
 * classification — composed into a decision-ready Markdown summary the agent speaks
 * verbatim. Read-only. Scalar I/O per Agentforce platform rules.
 */
public with sharing class AmaizeFindCompetingGrants {

    public class Request {
        @InvocableVariable(label='Country' description='Country of the funding scope, e.g. Kenya' required=true)
        public String country;
        @InvocableVariable(label='Business Unit' description='Program / business unit, e.g. Core Program' required=true)
        public String businessUnit;
        @InvocableVariable(label='Fiscal Year' description='Fiscal year, e.g. 2027' required=false)
        public Integer fiscalYear;
        @InvocableVariable(label='Sub-Unit' description='Sub-Unit to narrow the scope. Use N/A when not applicable.' required=false)
        public String subUnit;
        @InvocableVariable(label='Department' description='Department. Use N/A when not applicable.' required=false)
        public String department;
        @InvocableVariable(label='Cost Type' description='Cost Type. Use N/A when not applicable.' required=false)
        public String costType;
        @InvocableVariable(label='Cost Category' description='Cost Category. Use N/A when not applicable.' required=false)
        public String costCategory;
    }

    public class Result {
        @InvocableVariable(label='Summary' description='Decision-ready competing-grants analysis to show the user.')
        public String summary;
        @InvocableVariable(label='Severity' description='No Material / Moderate / High Competition, or Critical / Over-allocated; NEEDS_INFO or NOT_FOUND otherwise.')
        public String severity;
        @InvocableVariable(label='Combined Pipeline' description='Combined competing (Likely+Pipeline) funding for the scope.')
        public Decimal combinedPipeline;
        @InvocableVariable(label='Remaining Headroom' description='Remaining secured headroom for the scope.')
        public Decimal remainingHeadroom;
        @InvocableVariable(label='Results JSON' description='Machine-readable competing-grants detail.')
        public String resultsJson;
        @InvocableVariable(label='Found' description='True when the scope resolved to at least one Budget Line.')
        public Boolean found;
    }

    @InvocableMethod(
        label='Find Competing Grants'
        description='Finds grant Opportunities competing for the same program funding scope, compares combined competing pipeline to remaining headroom, runs closing scenarios, and classifies the competition.')
    public static List<Result> find(List<Request> requests) {
        List<Result> results = new List<Result>();
        CompetingGrantsService service = new CompetingGrantsService();
        for (Request req : requests) {
            results.add(answerOne(req, service));
        }
        return results;
    }

    private static Result answerOne(Request req, CompetingGrantsService service) {
        BudgetLineDimensions d = new BudgetLineDimensions();
        d.country = req.country;
        d.businessUnit = req.businessUnit;
        d.fiscalYear = (req.fiscalYear != null) ? String.valueOf(req.fiscalYear) : null;
        d.subUnit = req.subUnit;
        d.department = req.department;
        d.costType = req.costType;
        d.costCategory = req.costCategory;

        CompetingGrantsResult a = service.analyze(d);
        Result r = new Result();
        switch on a.status {
            when FOUND {
                r.found = true;
                r.severity = a.severity;
                r.combinedPipeline = a.combinedCompeting;
                r.remainingHeadroom = a.securedHeadroom;
                r.summary = compose(a);
                r.resultsJson = JSON.serialize(new Map<String, Object>{
                    'severity' => a.severity, 'combinedCompeting' => a.combinedCompeting,
                    'securedHeadroom' => a.securedHeadroom, 'forecastHeadroom' => a.forecastHeadroom,
                    'potentialExcess' => a.potentialExcess, 'grantCount' => a.grants.size()
                });
            }
            when NEEDS_INFO {
                r.found = false; r.severity = 'NEEDS_INFO';
                r.summary = 'I can check that. I still need the '
                    + HeadroomFormat.humanJoin(a.missingDimensions)
                    + ' to identify the funding scope. If a dimension has no applicable value, specify N/A.';
                r.resultsJson = '{"status":"NEEDS_INFO"}';
            }
            when else {
                r.found = false; r.severity = 'NOT_FOUND';
                r.summary = 'I couldn\'t find a Budget Line for '
                    + HeadroomFormat.humanJoin(a.requested.suppliedPhrases())
                    + ', so I can\'t assess competition for it. Please check those values, '
                    + 'or ask Grants Finance whether this scope exists in the current scenario.';
                r.resultsJson = '{"status":"NOT_FOUND"}';
            }
        }
        return r;
    }

    private static String compose(CompetingGrantsResult a) {
        String iso = a.currencyIsoCode;
        String scope = a.businessUnit + ' in ' + a.country
            + (a.fiscalYear != null ? ' for FY' + a.fiscalYear : '');

        List<CompetingGrant> competing = new List<CompetingGrant>();
        for (CompetingGrant g : a.grants) { if (g.isCompetingPipeline()) { competing.add(g); } }

        // ---- Summary ----
        String head;
        if (competing.isEmpty()) {
            head = '**Competing Grants Summary**\nNo pipeline grants are currently competing for '
                + scope + '. Remaining secured headroom is ' + AmaizeFormat.money(a.securedHeadroom, iso) + '.';
        } else {
            head = '**Competing Grants Summary**\n' + competing.size() + ' pipeline '
                + (competing.size() == 1 ? 'opportunity is' : 'opportunities are') + ' targeting '
                + scope + '. Together they represent ' + AmaizeFormat.money(a.combinedCompeting, iso)
                + ' of competing funding against ' + AmaizeFormat.money(a.securedHeadroom, iso)
                + ' of remaining secured headroom. '
                + (a.potentialExcess > 0
                    ? 'If all close at their proposed amounts, the scope would exceed available headroom by '
                        + AmaizeFormat.money(a.potentialExcess, iso) + '.'
                    : 'Current headroom could accommodate them.');
        }

        // ---- Program Headroom ----
        String hr = '\n\n**Program Headroom** — ' + scope
            + (a.lineCount > 1 ? ' (' + a.lineCount + ' budget lines)' : '')
            + '\nBudget ' + AmaizeFormat.money(a.budgetCost, iso)
            + ' · Secured ' + AmaizeFormat.money(a.securedFunding, iso)
            + ' · Likely ' + AmaizeFormat.money(a.likelyFunding, iso)
            + ' · Pipeline ' + AmaizeFormat.money(a.pipelineFunding, iso)
            + '\nRemaining **secured** headroom ' + AmaizeFormat.money(a.securedHeadroom, iso)
            + '; **forecast** headroom (after likely + pipeline) ' + AmaizeFormat.money(a.forecastHeadroom, iso) + '.';

        // ---- Competing Opportunities table ----
        String table = '';
        if (!competing.isEmpty()) {
            table = '\n\n**Competing Opportunities**\n'
                + '| Opportunity | Donor | Amount | Stage | Prob | Close | Owner |\n'
                + '|---|---|---|---|---|---|---|\n';
            for (CompetingGrant g : competing) {
                table += '| ' + nz(g.opportunityName) + ' | ' + nz(g.donor) + ' | '
                    + AmaizeFormat.money(g.allocatedAmount, iso) + ' | ' + nz(g.stage) + ' | '
                    + (g.probability == null ? '—' : String.valueOf(Integer.valueOf(g.probability)) + '%') + ' | '
                    + (g.closeDate == null ? '—' : g.closeDate.year() + '-' + String.valueOf(g.closeDate.month()).leftPad(2,'0')) + ' | '
                    + nz(g.owner) + ' |\n';
            }
        }

        // ---- Scenario Impact (cumulative, most advanced first) ----
        String scen = '';
        if (!competing.isEmpty()) {
            scen = '\n\n**Scenario Impact** (cumulative, most advanced first)';
            Decimal running = a.securedHeadroom;
            for (CompetingGrant g : competing) {
                running -= g.allocatedAmount;
                scen += '\nIf ' + shortName(g.opportunityName) + ' closes → remaining '
                    + AmaizeFormat.money(running, iso) + (running < 0 ? ' _(over-allocated)_' : '');
            }
            scen += '\nProbability-weighted competing pipeline ≈ ' + AmaizeFormat.money(a.probWeightedCompeting, iso)
                + ' → ~' + AmaizeFormat.money(a.securedHeadroom - a.probWeightedCompeting, iso) + ' left.';
        }

        // ---- Severity + risks + coordination ----
        String verdict = '\n\n**Competition severity: ' + a.severity + '.**';
        String risks = '';
        List<String> notes = new List<String>();
        for (CompetingGrant g : a.grants) {
            if (g.isCompetingPipeline() && g.onlyUnconfirmed) {
                notes.add(shortName(g.opportunityName) + ' has no confirmed/approved allocation yet, so its scope is unconfirmed');
            }
        }
        if (a.forecastHeadroom < 0) {
            notes.add('secured + likely + pipeline funding already exceeds the budget for this scope');
        }
        if (!notes.isEmpty()) { risks = '\n\n**Risks / Considerations** — ' + HeadroomFormat.humanJoin(notes) + '.'; }

        String coord = '';
        if (a.severity.startsWith('High') || a.severity.startsWith('Critical')) {
            coord = '\n\n**Suggested Coordination** — Consider aligning with Grants Finance and the '
                + 'relevant Relationship Managers before advancing these proposals at their current '
                + 'amounts, as together they approach or exceed remaining program headroom.';
        }

        return head + hr + table + scen + verdict + risks + coord;
    }

    private static String nz(String s) { return String.isBlank(s) ? '—' : s; }

    /** Funder-style short name: the part before the first dash, else the whole name. */
    private static String shortName(String name) {
        if (String.isBlank(name)) { return 'this opportunity'; }
        return name.split('[–-]', 2)[0].trim();
    }
}
