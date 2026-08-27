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

        // 1. Summary (conclusion first)
        String s;
        if (a.noAllocations) {
            s = '**Competing Grants Summary**\nI found the governed ' + scope + ' Budget Line population ('
                + a.budgetLineCount + ' lines), but no Funding Allocations are currently linked to them, so competition cannot be assessed.';
        } else if (competing.isEmpty()) {
            s = '**Competing Grants Summary**\nNo pipeline grants are currently competing for ' + scope
                + '. Remaining secured headroom is ' + AmaizeFormat.money(a.securedHeadroom, iso) + '.';
        } else {
            s = '**Competing Grants Summary**\n' + competing.size() + ' pipeline '
                + (competing.size() == 1 ? 'opportunity totaling ' : 'opportunities totaling ')
                + AmaizeFormat.money(a.combinedCompeting, iso) + ' of mapped exposure are competing for ' + scope
                + '. Current secured headroom is ' + AmaizeFormat.money(a.securedHeadroom, iso) + ', so '
                + (a.minimumAdjustmentRequired > 0
                    ? 'they could not all fit at their currently allocated amounts.'
                    : 'they can currently be accommodated.');
        }

        // 2. Risk & Confidence
        String rc = '\n\n**Risk & Confidence**\n- Competition Risk: ' + a.severity
            + '\n- Analysis Confidence: ' + a.analysisConfidence;
        if (!a.confidenceReasons.isEmpty()) { rc += ' — ' + String.join(a.confidenceReasons, ' '); }

        // 3. Why they compete
        String why = '\n\n**Why They Compete**\n' + (competing.isEmpty()
            ? 'No competing pipeline exposure was found on this governed Budget Line population.'
            : 'These opportunities are competing because their Funding Allocations map to Budget Lines within the same governed '
                + scope + ' headroom population (' + a.budgetLineCount + ' budget lines) — a confirmed relationship through '
                + 'the allocations, not merely a shared program name.');

        // 4. Headroom position
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

        // 5. Competing opportunities
        String co = '';
        if (!competing.isEmpty()) {
            List<String> blocks = new List<String>();
            for (CompetingGrant g : competing) { blocks.add(grantBlock(g, iso)); }
            co = '\n\n**Competing Opportunities**\n' + String.join(blocks, '\n');
        }

        // 6. What can fit
        String fit = '';
        if (!a.whatCanFit.isEmpty()) {
            List<String> lines = new List<String>();
            for (CompetingGrantsResult.FitScenario f : a.whatCanFit) {
                lines.add('- ' + f.label + ': ' + AmaizeFormat.money(f.exposure, iso)
                    + (f.fits ? ' — fits' : ' — exceeds headroom by ' + AmaizeFormat.money(f.excess, iso)));
            }
            fit = '\n\n**What Can Fit** (competing exposure vs. secured headroom)\n' + String.join(lines, '\n')
                + (a.exhaustiveCombinations ? '' : '\n_(showing key scenarios; many opportunities present)_');
        }

        // 7. Minimum adjustment
        String adj = a.minimumAdjustmentRequired > 0
            ? '\n\n**Minimum Adjustment** — To accommodate all competing opportunities at their currently mapped amounts, '
                + 'about ' + AmaizeFormat.money(a.minimumAdjustmentRequired, iso) + ' would need to be reduced, reallocated '
                + 'to other eligible headroom, or supported by additional eligible budget capacity.'
            : '';

        // 8. Funding / allocation coverage
        String cov = '';
        List<String> covNotes = new List<String>();
        for (CompetingGrant g : competing) {
            if (g.unmappedAmount != null && g.unmappedAmount > 0) {
                covNotes.add(shortName(g.opportunityName) + ' has ' + AmaizeFormat.money(g.unmappedAmount, iso)
                    + ' of its ' + AmaizeFormat.money(g.opportunityAmount, iso) + ' amount not yet mapped through allocations'
                    + (g.allocationCoveragePct != null ? ' (' + g.allocationCoveragePct.intValue() + '% mapped)' : '')
                    + ' — excluded from this competition until allocated');
            }
        }
        if (!covNotes.isEmpty()) { cov = '\n\n**Funding / Allocation Coverage**\n- ' + String.join(covNotes, '\n- ') + '.'; }

        // 9. Timing
        String timing = '\n\n**Timing** — ' + a.timingCollisionStatus
            + '. All competing allocations fall in the same fiscal-year population; finer restricted-period dates '
            + 'are not available in the data model, so timing is assessed at the fiscal-year grain.';

        // 10. Data quality
        List<String> dq = new List<String>{ 'Analysis Confidence: ' + a.analysisConfidence };
        if (a.distinctOwnerCount > 1) {
            dq.add(competing.size() + ' competing opportunities across ' + a.distinctOwnerCount + ' owners — coordination may be useful');
        }
        if (a.allocationsMissingGiftCommitment > 0) {
            dq.add(a.allocationsMissingGiftCommitment + ' allocation'
                + (a.allocationsMissingGiftCommitment == 1 ? ' has' : 's have') + ' no linked Gift Commitment');
        }
        String dqs = '\n\n**Data Quality**\n- ' + String.join(dq, '\n- ')
            + '\n\n_Analysis based on Salesforce data current as of ' + a.retrievalTime.format('yyyy-MM-dd HH:mm') + '._';

        // 11. Recommended next step
        String next = '';
        if (a.severity != null && (a.severity.startsWith('High') || a.severity.startsWith('Critical'))) {
            next = '\n\n**Recommended Next Step** — Combined competing exposure approaches or exceeds governed secured '
                + 'headroom; review proposal sizing and allocation flexibility with Grants Finance and the opportunity '
                + 'owners before these advance further.';
        }

        // 12. Intelligent next questions (context-driven)
        String nq = nextQuestions(a, competing);

        return s + rc + why + hp + co + fit + adj + cov + timing + dqs + next + nq;
    }

    /** One competing opportunity block: exposure split, concentration, coverage, record links. */
    private static String grantBlock(CompetingGrant g, String iso) {
        String s = '- ' + AmaizeLink.md(g.opportunityName, 'Opportunity', g.opportunityId)
            + (g.donorName != null ? ' — ' + AmaizeLink.md(g.donorName, 'Account', g.accountId) : '');
        s += '\n  - Exposure to this scope: ' + AmaizeFormat.money(g.allocatedAmount, iso)
            + ' (Secured ' + AmaizeFormat.money(g.securedExposure, iso)
            + ' / Likely ' + AmaizeFormat.money(g.likelyExposure, iso)
            + ' / Pipeline ' + AmaizeFormat.money(g.pipelineExposure, iso) + ')';
        if (g.headroomConsumptionPct != null) {
            s += '\n  - Share of current secured headroom: ' + g.headroomConsumptionPct.intValue() + '%';
        }
        if (g.opportunityAmount != null) {
            s += '\n  - Opportunity Amount: ' + AmaizeFormat.money(g.opportunityAmount, iso)
                + ' _(context — not the headroom exposure)_'
                + (g.allocationCoveragePct != null ? ' · ' + g.allocationCoveragePct.intValue() + '% mapped through allocations' : '');
        }
        s += '\n  - Stage: ' + nz(g.stage)
            + (g.probability != null ? ' · ' + String.valueOf(Integer.valueOf(g.probability)) + '%' : '')
            + (g.closeDate != null ? ' · close ' + g.closeDate.year() + '-' + String.valueOf(g.closeDate.month()).leftPad(2,'0') : '')
            + (String.isNotBlank(g.owner) ? ' · owner ' + g.owner : '')
            + ' · ' + g.allocationCount + ' allocation' + (g.allocationCount == 1 ? '' : 's')
            + ' across ' + g.budgetLineIds.size() + ' budget line' + (g.budgetLineIds.size() == 1 ? '' : 's');
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

    /** Context-driven follow-up suggestions (not the same generic list every time). */
    private static String nextQuestions(CompetingGrantsResult a, List<CompetingGrant> competing) {
        List<String> qs = new List<String>();
        if (competing.size() >= 2) { qs.add('"What if the top two opportunities close?"'); }
        if (a.minimumAdjustmentRequired > 0) { qs.add('"What would need to be reallocated for all to fit?"'); }
        if (a.distinctOwnerCount > 1) { qs.add('"Who owns these opportunities?"'); }
        if (!competing.isEmpty()) { qs.add('"Which opportunity is closest to closing?"'); }
        if (a.allocationsMissingGiftCommitment > 0 || !competing.isEmpty()) { qs.add('"Show me the restrictions behind these."'); }
        qs.add('"Show me the underlying allocations."');
        // Keep it to three relevant suggestions.
        List<String> top = new List<String>();
        for (Integer i = 0; i < qs.size() && i < 3; i++) { top.add(qs[i]); }
        return top.isEmpty() ? '' : '\n\n**You might also ask:** ' + String.join(top, ' · ');
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
                'donorName' => g.donorName, 'owner' => g.owner,
                'opportunityAmount' => g.opportunityAmount,
                'exposureToCurrentScope' => g.allocatedAmount, 'exposureElsewhere' => g.exposureElsewhere,
                'totalMappedAllocation' => g.totalMappedAllocation, 'unmappedAmount' => g.unmappedAmount,
                'allocationCoveragePercentage' => g.allocationCoveragePct,
                'headroomConsumptionPercentage' => g.headroomConsumptionPct,
                'securedExposure' => g.securedExposure, 'likelyExposure' => g.likelyExposure,
                'pipelineExposure' => g.pipelineExposure, 'allocationCount' => g.allocationCount,
                'budgetLineCount' => g.budgetLineIds.size(), 'distinctRestrictionCount' => g.restrictionIds.size(),
                'stage' => g.stage, 'probability' => g.probability
            });
        }
        List<Map<String, Object>> fits = new List<Map<String, Object>>();
        for (CompetingGrantsResult.FitScenario f : a.whatCanFit) {
            fits.add(new Map<String, Object>{ 'label' => f.label, 'exposure' => f.exposure, 'fits' => f.fits, 'excess' => f.excess });
        }
        return JSON.serialize(new Map<String, Object>{
            'category' => a.category, 'country' => a.country, 'fiscalYear' => a.fiscalYear,
            'budgetLineCount' => a.budgetLineCount, 'budgetAmount' => a.budgetAmount,
            'securedFunding' => a.securedFunding, 'likelyFunding' => a.likelyFunding,
            'pipelineFunding' => a.pipelineFunding, 'forecastFunding' => a.forecastFunding,
            'securedHeadroom' => a.securedHeadroom, 'forecastHeadroom' => a.forecastHeadroom,
            'headroomStatus' => a.headroomStatus,
            'analysis' => new Map<String, Object>{
                'competitionSeverity' => a.severity, 'analysisConfidence' => a.analysisConfidence,
                'confidenceReasons' => a.confidenceReasons,
                'competingOpportunityCount' => a.grants.size(),
                'combinedCompetingExposure' => a.combinedCompeting,
                'combinedLikelyExposure' => a.combinedLikelyExposure,
                'combinedPipelineExposure' => a.combinedPipelineExposure,
                'availableHeadroom' => a.securedHeadroom,
                'minimumAdjustmentRequired' => a.minimumAdjustmentRequired,
                'distinctOwnerCount' => a.distinctOwnerCount,
                'timingCollisionStatus' => a.timingCollisionStatus,
                'unmappedOpportunityAmountTotal' => a.unmappedOpportunityAmountTotal,
                'exhaustiveCombinations' => a.exhaustiveCombinations
            },
            'whatCanFit' => fits, 'opportunities' => opps,
            'retrievalTime' => a.retrievalTime
        });
    }
}
