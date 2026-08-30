/**
 * AmaizeOpportunityCompetition — Opportunity-start competition action for the Competing Grants
 * Analysis sub-agent. Given a grant name ("what competes with the Gates opportunity?"), it
 * finds the Budget Lines the grant's allocations touch, determines the governed Headroom
 * scopes, and reports the competition for EACH scope (never collapsed) — the focus grant's
 * exposure vs. the other opportunities consuming the same governed headroom, with links.
 * Read-only. Scalar I/O.
 */
public with sharing class AmaizeOpportunityCompetition {

    public class Request {
        @InvocableVariable(label='Opportunity Name' description='The grant/opportunity to analyze competition for.' required=true)
        public String opportunityName;
    }

    public class Result {
        @InvocableVariable(label='Summary' description='Per-scope competition analysis for the grant, with record links.')
        public String summary;
        @InvocableVariable(label='Found' description='True when the grant resolved and touches at least one governed scope.')
        public Boolean found;
        @InvocableVariable(label='Results JSON' description='Machine-readable per-scope competition detail.')
        public String resultsJson;
    }

    @InvocableMethod(
        label='Analyze Opportunity Competition'
        description='Starts from a named grant, finds the governed Headroom scopes its allocations touch, and reports the other opportunities competing for the same headroom in each scope.')
    public static List<Result> analyze(List<Request> requests) {
        List<Result> results = new List<Result>();
        CompetingGrantsService svc = new CompetingGrantsService();
        for (Request req : requests) {
            results.add(answerOne(req, svc));
        }
        return results;
    }

    private static Result answerOne(Request req, CompetingGrantsService svc) {
        OpportunityCompetition a = svc.analyzeForOpportunity(req.opportunityName);
        Result r = new Result();
        switch on a.status {
            when FOUND { r.found = true; r.summary = compose(a); r.resultsJson = json(a); }
            when AMBIGUOUS {
                r.found = false;
                r.summary = 'I found more than one grant matching "' + req.opportunityName + '":\n  • '
                    + String.join(a.ambiguousChoices, '\n  • ') + '\nWhich one did you mean?';
                r.resultsJson = '{"status":"AMBIGUOUS"}';
            }
            when NO_ALLOCATIONS {
                r.found = false;
                r.summary = AmaizeLink.md(a.opportunityName, 'Opportunity', a.opportunityId)
                    + ' has no funding recorded against a Budget Line, so it is not currently '
                    + 'competing for any program Headroom. Its opportunity amount is fundraising '
                    + 'context only until it is allocated.';
                r.resultsJson = '{"status":"NO_ALLOCATIONS"}';
            }
            when NEEDS_INFO {
                r.found = false;
                r.summary = 'Which grant should I analyze competition for? Please give the opportunity name.';
                r.resultsJson = '{"status":"NEEDS_INFO"}';
            }
            when else {
                r.found = false;
                r.summary = 'I couldn\'t find a grant matching "' + req.opportunityName
                    + '". Please give the exact opportunity name.';
                r.resultsJson = '{"status":"NOT_FOUND"}';
            }
        }
        return r;
    }

    private static String compose(OpportunityCompetition a) {
        String iso = a.currencyIsoCode;
        String head = '**Competition for ' + AmaizeLink.md(a.opportunityName, 'Opportunity', a.opportunityId) + '**'
            + (a.donorName != null ? ' — ' + AmaizeLink.md(a.donorName, 'Account', a.accountId) : '')
            + (a.opportunityAmount != null ? ' · opportunity amount ' + AmaizeFormat.money(a.opportunityAmount, iso) : '')
            + (a.stage != null ? ' · stage ' + a.stage : '')
            + '\n\nThis grant\'s funding touches ' + a.scopesTouched + ' Headroom scope'
            + (a.scopesTouched == 1 ? '' : 's')
            + (a.capped ? ' (showing the ' + a.scopes.size() + ' largest by this grant\'s contribution)' : '')
            + '. Each is analyzed separately below.';

        List<String> blocks = new List<String>();
        for (OpportunityCompetition.ScopeCompetition sc : a.scopes) {
            blocks.add(scopeBlock(a, sc, iso));
        }
        return head + '\n\n' + String.join(blocks, '\n\n');
    }

    private static String scopeBlock(OpportunityCompetition a, OpportunityCompetition.ScopeCompetition sc, String iso) {
        CompetingGrantsResult c = sc.competition;
        String title = '**' + sc.category + ' · ' + sc.country
            + (sc.fiscalYear != null ? ' · ' + sc.fiscalYear : '') + '** — ' + c.severity;
        String body = '\n- This grant\'s contribution here: ' + AmaizeFormat.money(sc.focusExposure, iso)
            + '\n- Secured headroom: ' + AmaizeFormat.money(c.securedHeadroom, iso)
            + ' · total competing (Likely+Pipeline): ' + AmaizeFormat.money(c.combinedCompeting, iso)
            + (c.minimumAdjustmentRequired > 0
                ? ' · **' + AmaizeFormat.money(c.minimumAdjustmentRequired, iso) + ' over headroom if all close**' : '');

        // Other competing opportunities (exclude the focus grant), most advanced first.
        List<String> others = new List<String>();
        for (CompetingGrant g : c.grants) {
            if (g.opportunityId == a.opportunityId) { continue; }
            if (!g.isCompetingPipeline()) { continue; }
            others.add('  - ' + AmaizeLink.md(g.opportunityName, 'Opportunity', g.opportunityId)
                + (g.donorName != null ? ' (' + g.donorName + ')' : '')
                + ': ' + AmaizeFormat.money(g.likelyExposure + g.pipelineExposure, iso) + ' competing'
                + (g.stage != null ? ' · ' + g.stage : '')
                + (g.probability != null ? ' · ' + String.valueOf(Integer.valueOf(g.probability)) + '%' : ''));
        }
        String otherBlock = others.isEmpty()
            ? '\n- No other opportunities are competing for this scope.'
            : '\n- Other competing opportunities:\n' + String.join(others, '\n');
        return title + body + otherBlock;
    }

    private static String json(OpportunityCompetition a) {
        List<Map<String, Object>> scopes = new List<Map<String, Object>>();
        for (OpportunityCompetition.ScopeCompetition sc : a.scopes) {
            CompetingGrantsResult c = sc.competition;
            Integer otherCompetitors = 0;
            for (CompetingGrant g : c.grants) {
                if (g.opportunityId != a.opportunityId && g.isCompetingPipeline()) { otherCompetitors++; }
            }
            scopes.add(new Map<String, Object>{
                'category' => sc.category, 'country' => sc.country, 'fiscalYear' => sc.fiscalYear,
                'focusExposure' => sc.focusExposure, 'securedHeadroom' => c.securedHeadroom,
                'combinedCompeting' => c.combinedCompeting, 'minimumAdjustmentRequired' => c.minimumAdjustmentRequired,
                'severity' => c.severity, 'otherCompetitorCount' => otherCompetitors
            });
        }
        return JSON.serialize(new Map<String, Object>{
            'opportunityId' => a.opportunityId, 'opportunityName' => a.opportunityName,
            'opportunityUrl' => AmaizeLink.recordUrl('Opportunity', a.opportunityId),
            'opportunityAmount' => a.opportunityAmount, 'scopesTouched' => a.scopesTouched,
            'capped' => a.capped, 'scopes' => scopes
        });
    }
}
