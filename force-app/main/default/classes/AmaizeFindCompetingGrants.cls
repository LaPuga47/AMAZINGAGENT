/**
 * AmaizeFindCompetingGrants — governed Competing Grants Analysis action.
 *
 * Resolves the SAME governed Budget Line population as Headroom Analysis (category + country
 * + fiscal year), aggregates the governed Headroom fields across all qualifying lines, then
 * reports the Opportunities competing for that population — by allocation EXPOSURE (not
 * Opportunity Amount), split by type — with clickable Salesforce record links, competition
 * severity, a closing scenario, and data-quality notes. Read-only. Scalar I/O.
 */
public with sharing class AmaizeFindCompetingGrants {

    public class Request {
        @InvocableVariable(label='Program' description='Headroom category / program, e.g. Core Program, Rural Retail, Market Access, Trees, System Change Extension.' required=true)
        public String program;
        @InvocableVariable(label='Country' description='Country of the Budget Lines, e.g. Kenya. Authoritative filter.' required=true)
        public String country;
        @InvocableVariable(label='Fiscal Year' description='Fiscal year, e.g. 2027. Defaults to the current scenario when omitted.' required=false)
        public Integer fiscalYear;
    }

    public class Result {
        @InvocableVariable(label='Summary' description='Decision-ready competing-grants analysis (governed headroom + competing opportunities with record links).')
        public String summary;
        @InvocableVariable(label='Severity' description='No Material / Moderate / High Competition, Critical / Over-allocated, or NONE / ZERO / NOT_CONFIGURED / NEEDS_INFO.')
        public String severity;
        @InvocableVariable(label='Results JSON' description='Machine-readable competing-grants detail.')
        public String resultsJson;
        @InvocableVariable(label='Found' description='True when the governed scope resolved to Budget Lines.')
        public Boolean found;
    }

    @InvocableMethod(
        label='Find Competing Grants'
        description='Finds the grant Opportunities competing for a governed Headroom population (category + country + fiscal year), by allocation exposure across all qualifying Budget Lines, with headroom totals identical to Headroom Analysis and clickable record links.')
    public static List<Result> find(List<Request> requests) {
        List<Result> results = new List<Result>();
        CompetingGrantsService service = new CompetingGrantsService();
        for (Request req : requests) {
            results.add(answerOne(req, service));
        }
        return results;
    }

    private static Result answerOne(Request req, CompetingGrantsService service) {
        String fy = (req.fiscalYear != null) ? String.valueOf(req.fiscalYear) : null;
        CompetingGrantsResult a = service.analyze(req.program, req.country, fy);
        Result r = new Result();
        r.severity = a.severity;
        switch on a.status {
            when FOUND {
                r.found = true;
                r.summary = compose(a);
                r.resultsJson = json(a);
            }
            when ZERO {
                r.found = false; r.severity = 'ZERO';
                r.summary = a.category + ' has no governed Headroom capacity in this model (it is defined as zero), '
                    + 'so a Budget-Line competition analysis does not apply.';
                r.resultsJson = '{"status":"ZERO"}';
            }
            when NOT_CONFIGURED {
                r.found = false; r.severity = 'NOT_CONFIGURED';
                r.summary = 'The governed Headroom aggregation rule for "' + a.category
                    + '" has not yet been configured, so reliable competing-grants analysis cannot be performed for it yet.';
                r.resultsJson = '{"status":"NOT_CONFIGURED"}';
            }
            when NONE {
                r.found = false; r.severity = 'NONE';
                r.summary = 'No qualifying Budget Line records were found for the requested scope ('
                    + a.category + ', ' + a.country + (a.fiscalYear != null ? ', FY' + a.fiscalYear : '') + ').';
                r.resultsJson = '{"status":"NONE"}';
            }
            when else {
                r.found = false; r.severity = 'NEEDS_INFO';
                r.summary = 'I can run that. I still need the ' + HeadroomFormat.humanJoin(a.missing) + '.';
                r.resultsJson = '{"status":"NEEDS_INFO"}';
            }
        }
        return r;
    }

    private static String compose(CompetingGrantsResult a) {
        String iso = a.currencyIsoCode;
        String scope = a.category + ' — ' + a.country + (a.fiscalYear != null ? ' — FY' + a.fiscalYear : '');

        List<CompetingGrant> competing = new List<CompetingGrant>();
        for (CompetingGrant g : a.grants) { if (g.isCompetingPipeline()) { competing.add(g); } }

        // Summary
        String summ;
        if (a.noAllocations) {
            summ = '**Competing Grants Summary**\nI found the governed ' + scope + ' Budget Line population ('
                + a.budgetLineCount + ' lines), but no Funding Allocations are currently linked to those Budget Lines.';
        } else if (competing.isEmpty()) {
            summ = '**Competing Grants Summary**\nNo pipeline grants are currently competing for ' + scope
                + '. Remaining secured headroom is ' + AmaizeFormat.money(a.securedHeadroom, iso) + '.';
        } else {
            summ = '**Competing Grants Summary**\n' + competing.size() + ' pipeline '
                + (competing.size() == 1 ? 'opportunity is' : 'opportunities are') + ' mapped to the ' + scope
                + ' headroom population. Combined mapped pipeline exposure is '
                + AmaizeFormat.money(a.combinedCompeting, iso) + ' against '
                + AmaizeFormat.money(a.securedHeadroom, iso) + ' of governed secured headroom'
                + (a.potentialExcess > 0
                    ? '; if all became secured at their allocated amounts they would exceed it by '
                        + AmaizeFormat.money(a.potentialExcess, iso) + '.'
                    : '.');
        }

        // Headroom position (governed — identical to Headroom Analysis)
        String hp = '\n\n**Headroom Position** — ' + scope
            + (a.scenarioLabel != null ? ' (' + a.scenarioLabel + ')' : '')
            + '\n- Budget Amount: ' + AmaizeFormat.money(a.budgetAmount, iso)
            + '\n- Secured Funding: ' + AmaizeFormat.money(a.securedFunding, iso)
            + '\n- Likely Funding: ' + AmaizeFormat.money(a.likelyFunding, iso)
            + '\n- Pipeline Funding: ' + AmaizeFormat.money(a.pipelineFunding, iso)
            + '\n- Forecast Funding: ' + AmaizeFormat.money(a.forecastFunding, iso)
            + '\n- Secured Headroom: ' + AmaizeFormat.money(a.securedHeadroom, iso)
            + '\n- Forecast Headroom: ' + AmaizeFormat.money(a.forecastHeadroom, iso)
            + '\n- Headroom Status: ' + a.headroomStatus
            + '\n- Budget Lines Included: ' + a.budgetLineCount;

        // Competing opportunities (exposure, not opportunity amount) with record links
        String co = '';
        if (!competing.isEmpty()) {
            List<String> blocks = new List<String>();
            for (CompetingGrant g : competing) {
                blocks.add(grantBlock(g, iso));
            }
            co = '\n\n**Competing Opportunities**\n' + String.join(blocks, '\n');
        }

        // Scenario impact (cumulative, most advanced first)
        String scen = '';
        if (!competing.isEmpty()) {
            scen = '\n\n**Scenario Impact** (cumulative, most advanced first)';
            Decimal running = a.securedHeadroom;
            for (CompetingGrant g : competing) {
                running -= (g.likelyExposure + g.pipelineExposure);
                scen += '\n- If ' + shortName(g.opportunityName) + ' becomes secured → remaining '
                    + AmaizeFormat.money(running, iso) + (running < 0 ? ' _(over-allocated)_' : '');
            }
        }

        // Data quality
        String dq = '';
        List<String> notes = new List<String>();
        if (a.allocationsMissingGiftCommitment > 0) {
            notes.add(a.allocationsMissingGiftCommitment + ' allocation'
                + (a.allocationsMissingGiftCommitment == 1 ? '' : 's') + ' have no linked Gift Commitment');
        }
        if (!notes.isEmpty()) { dq = '\n\n**Data Quality** — ' + HeadroomFormat.humanJoin(notes) + '.'; }

        // Next step
        String next = '';
        if (a.severity != null && (a.severity.startsWith('High') || a.severity.startsWith('Critical'))) {
            next = '\n\n**Recommended Next Step** — Combined pipeline exposure approaches or exceeds governed '
                + 'secured headroom; review proposal sizing and allocation flexibility with Grants Finance and the '
                + 'opportunity owners before these advance further.';
        }

        return summ + hp + co + scen + dq + '\n\n**Competition severity: ' + a.severity + '.**' + next;
    }

    /** One competing opportunity block: exposure split + record links. */
    private static String grantBlock(CompetingGrant g, String iso) {
        String oppLink = AmaizeLink.md(g.opportunityName, 'Opportunity', g.opportunityId);
        String s = '- ' + oppLink
            + (g.donorName != null ? ' — ' + AmaizeLink.md(g.donorName, 'Account', g.accountId) : '');
        s += '\n  - Exposure to this scope: ' + AmaizeFormat.money(g.allocatedAmount, iso)
            + ' (Secured ' + AmaizeFormat.money(g.securedExposure, iso)
            + ' / Likely ' + AmaizeFormat.money(g.likelyExposure, iso)
            + ' / Pipeline ' + AmaizeFormat.money(g.pipelineExposure, iso) + ')';
        if (g.opportunityAmount != null) {
            s += '\n  - Total Opportunity Amount: ' + AmaizeFormat.money(g.opportunityAmount, iso)
                + ' _(fundraising context — not the headroom exposure)_';
        }
        s += '\n  - Stage: ' + nz(g.stage)
            + (g.probability != null ? ' · ' + String.valueOf(Integer.valueOf(g.probability)) + '%' : '')
            + (g.closeDate != null ? ' · close ' + g.closeDate.year() + '-' + String.valueOf(g.closeDate.month()).leftPad(2,'0') : '')
            + (String.isNotBlank(g.owner) ? ' · owner ' + g.owner : '')
            + ' · ' + g.allocationCount + ' allocation' + (g.allocationCount == 1 ? '' : 's')
            + ' across ' + g.budgetLineIds.size() + ' budget line' + (g.budgetLineIds.size() == 1 ? '' : 's');
        // Distinct restriction + gift commitment links (deduped)
        Map<Id, String> restr = new Map<Id, String>();
        Map<Id, String> gc = new Map<Id, String>();
        for (Allocation__c al : g.allocations) {
            if (al.Restriction__c != null && al.Restriction__r != null) {
                restr.put(al.Restriction__c, AmaizeLink.md(al.Restriction__r.Name, 'Restriction__c', al.Restriction__c));
            }
            if (al.Restriction__r != null && al.Restriction__r.Gift_Commitment__c != null) {
                gc.put(al.Restriction__r.Gift_Commitment__c,
                    AmaizeLink.md(al.Restriction__r.Gift_Commitment__r.Name, 'GiftCommitment', al.Restriction__r.Gift_Commitment__c));
            }
        }
        if (!restr.isEmpty()) { s += '\n  - Restrictions: ' + String.join(new List<String>(restr.values()), ', '); }
        s += '\n  - Gift Commitment: ' + (gc.isEmpty() ? '_not linked_' : String.join(new List<String>(gc.values()), ', '));
        return s;
    }

    private static String nz(String v) { return String.isBlank(v) ? '—' : v; }

    private static String shortName(String name) {
        if (String.isBlank(name)) { return 'this opportunity'; }
        return name.split('[–-]', 2)[0].trim();
    }

    private static String json(CompetingGrantsResult a) {
        List<Map<String, Object>> opps = new List<Map<String, Object>>();
        for (CompetingGrant g : a.grants) {
            opps.add(new Map<String, Object>{
                'opportunityId' => g.opportunityId, 'opportunityName' => g.opportunityName,
                'opportunityUrl' => AmaizeLink.recordUrl('Opportunity', g.opportunityId),
                'donorName' => g.donorName, 'opportunityAmount' => g.opportunityAmount,
                'totalExposure' => g.allocatedAmount, 'securedExposure' => g.securedExposure,
                'likelyExposure' => g.likelyExposure, 'pipelineExposure' => g.pipelineExposure,
                'allocationCount' => g.allocationCount, 'budgetLineCount' => g.budgetLineIds.size(),
                'stage' => g.stage, 'probability' => g.probability
            });
        }
        return JSON.serialize(new Map<String, Object>{
            'category' => a.category, 'country' => a.country, 'fiscalYear' => a.fiscalYear,
            'budgetLineCount' => a.budgetLineCount, 'budgetAmount' => a.budgetAmount,
            'securedFunding' => a.securedFunding, 'likelyFunding' => a.likelyFunding,
            'pipelineFunding' => a.pipelineFunding, 'forecastFunding' => a.forecastFunding,
            'securedHeadroom' => a.securedHeadroom, 'forecastHeadroom' => a.forecastHeadroom,
            'headroomStatus' => a.headroomStatus, 'combinedCompeting' => a.combinedCompeting,
            'potentialExcess' => a.potentialExcess, 'severity' => a.severity, 'opportunities' => opps
        });
    }
}
