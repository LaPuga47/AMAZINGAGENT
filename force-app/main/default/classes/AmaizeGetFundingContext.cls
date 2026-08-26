/**
 * AmaizeGetFundingContext — the relationship-aware funding-lineage action for the Competing
 * Grants Analysis sub-agent. It answers "what funding is behind this Budget Line?" and
 * "where is this Opportunity's funding allocated?" by traversing the org's approved
 * relationships (Budget Line <- Allocation -> Restriction -> Gift Commitment -> Opportunity
 * -> donor), returning a grounded, decision-ready summary with data-quality notes.
 *
 * Direction is inferred from the input: a grant name -> forward lineage (which Budget Lines
 * it funds); otherwise a country + business unit scope -> backward lineage (which grants and
 * donors fund it) plus competing-grants insight. Read-only. Scalar I/O.
 */
public with sharing class AmaizeGetFundingContext {

    public class Request {
        @InvocableVariable(label='Opportunity Name' description='Grant/opportunity name to trace forward to the Budget Lines it funds. Leave blank to trace a Budget Line scope instead.' required=false)
        public String opportunityName;
        @InvocableVariable(label='Country' description='Country of the Budget Line scope, e.g. Kenya' required=false)
        public String country;
        @InvocableVariable(label='Business Unit' description='Program / business unit, e.g. Core Program' required=false)
        public String businessUnit;
        @InvocableVariable(label='Fiscal Year' description='Fiscal year, e.g. 2027' required=false)
        public Integer fiscalYear;
        @InvocableVariable(label='Sub-Unit' description='Sub-Unit. Use N/A when not applicable.' required=false)
        public String subUnit;
        @InvocableVariable(label='Department' description='Department. Use N/A when not applicable.' required=false)
        public String department;
        @InvocableVariable(label='Cost Type' description='Cost Type. Use N/A when not applicable.' required=false)
        public String costType;
        @InvocableVariable(label='Cost Category' description='Cost Category. Use N/A when not applicable.' required=false)
        public String costCategory;
    }

    public class Result {
        @InvocableVariable(label='Summary' description='Decision-ready funding-context / lineage answer to show the user.')
        public String summary;
        @InvocableVariable(label='Found' description='True when the starting record resolved and lineage was returned.')
        public Boolean found;
        @InvocableVariable(label='Context JSON' description='Machine-readable funding-context detail.')
        public String contextJson;
    }

    @InvocableMethod(
        label='Get Funding Context'
        description='Traces the funding lineage around a Budget Line scope or a named grant — the linked allocations, restrictions, gift commitments, opportunities and donors — with headroom and competing-grants insight.')
    public static List<Result> get(List<Request> requests) {
        List<Result> results = new List<Result>();
        FundingContextService svc = new FundingContextService();
        for (Request req : requests) {
            results.add(answerOne(req, svc));
        }
        return results;
    }

    private static Result answerOne(Request req, FundingContextService svc) {
        Result r = new Result();
        FundingContext fc;
        if (String.isNotBlank(req.opportunityName)) {
            fc = svc.forOpportunity(req.opportunityName);
        } else if (String.isNotBlank(req.country) && String.isNotBlank(req.businessUnit)) {
            fc = svc.forBudgetLineScope(dims(req));
        } else {
            r.found = false;
            r.summary = 'To trace funding I need either a grant (opportunity) name, or a Budget Line '
                + 'scope — at minimum a country and business unit (a fiscal year and sub-unit help pin '
                + 'it down; say N/A where a dimension does not apply).';
            r.contextJson = '{"status":"NEEDS_INFO"}';
            return r;
        }

        switch on fc.status {
            when FOUND_BUDGET_LINE { r.found = true;  r.summary = budgetLineSummary(fc); }
            when FOUND_OPPORTUNITY { r.found = true;  r.summary = opportunitySummary(fc); }
            when AMBIGUOUS {
                r.found = false;
                r.summary = 'I found more than one grant matching that name:\n  • '
                    + String.join(fc.ambiguousChoices, '\n  • ') + '\nWhich one did you mean?';
            }
            when NEEDS_INFO {
                r.found = false;
                r.summary = 'I can trace that. I still need the '
                    + HeadroomFormat.humanJoin(fc.missingDimensions) + '.';
            }
            when else {
                r.found = false;
                r.summary = (fc.direction == 'opportunity')
                    ? 'I couldn\'t find a grant matching "' + req.opportunityName + '". '
                        + 'Please give the exact opportunity name.'
                    : 'I couldn\'t find a Budget Line for that scope, so there is no funding lineage to trace. '
                        + 'Please check the country, business unit, and fiscal year.';
            }
        }
        r.contextJson = json(fc);
        return r;
    }

    private static BudgetLineDimensions dims(Request req) {
        BudgetLineDimensions d = new BudgetLineDimensions();
        d.country = req.country; d.businessUnit = req.businessUnit;
        d.fiscalYear = (req.fiscalYear != null) ? String.valueOf(req.fiscalYear) : null;
        d.subUnit = req.subUnit; d.department = req.department;
        d.costType = req.costType; d.costCategory = req.costCategory;
        return d;
    }

    /* ---------------- Budget-Line direction: what funds this scope ---------------- */

    private static String budgetLineSummary(FundingContext fc) {
        String iso = fc.currencyIsoCode;
        String scope = fc.businessUnit + ' in ' + fc.country
            + (fc.fiscalYear != null ? ' for FY' + fc.fiscalYear : '');

        String head = '**Funding Context — ' + scope + '**'
            + (fc.budgetLines.size() > 1 ? ' (' + fc.budgetLines.size() + ' budget lines)' : '');

        String funding = '\n\n**Funding Summary**'
            + '\n- Budget: ' + AmaizeFormat.money(fc.budgetCost, iso)
            + '\n- Secured funding: ' + AmaizeFormat.money(fc.securedFunding, iso)
            + '\n- Remaining secured headroom: ' + AmaizeFormat.money(fc.securedHeadroom, iso);

        // Linked funding — one row per allocation with its full lineage.
        String linked;
        if (fc.allocations.isEmpty()) {
            linked = '\n\n**Linked Funding**\nNo funding allocations are currently linked to this scope.';
        } else {
            List<String> rows = new List<String>();
            Set<Id> opps = new Set<Id>();
            for (Allocation__c a : fc.allocations) {
                Opportunity o = opp(a);
                if (o != null) { opps.add(o.Id); }
                rows.add(allocationRow(a, iso));
            }
            linked = '\n\n**Linked Funding** (' + fc.allocations.size() + ' allocation'
                + (fc.allocations.size() == 1 ? '' : 's') + ' from ' + opps.size() + ' grant'
                + (opps.size() == 1 ? '' : 's') + ')\n' + String.join(rows, '\n');
        }

        // Competing-grants insight.
        String insight = '\n\n**Competing Grants Insight**\n';
        if (fc.combinedCompeting <= 0) {
            insight += 'No pipeline funding is competing for this scope. Severity: ' + fc.severity + '.';
        } else {
            insight += 'Combined competing (likely + pipeline) funding is '
                + AmaizeFormat.money(fc.combinedCompeting, iso) + ' against '
                + AmaizeFormat.money(fc.securedHeadroom, iso) + ' of remaining secured headroom'
                + (fc.potentialExcess > 0
                    ? ', a potential over-allocation of ' + AmaizeFormat.money(fc.potentialExcess, iso) + ' if all close'
                    : '')
                + '. Severity: ' + fc.severity + '.';
        }

        return head + funding + linked + insight + dataQuality(fc) + nextStep(fc);
    }

    private static String allocationRow(Allocation__c a, String iso) {
        Opportunity o = opp(a);
        String donor = (o != null && o.Account != null) ? o.Account.Name : null;
        String restr = (a.Restriction__r != null) ? a.Restriction__r.Business_Unit__c : null;
        Boolean gc = a.Restriction__r != null && a.Restriction__r.Gift_Commitment__r != null;
        return '- **' + (o != null ? o.Name : '(grant not linked)') + '**'
            + (donor != null ? ' — ' + donor : '')
            + ': ' + AmaizeFormat.money(a.Funds_Allocated__c, iso)
            + ' _(' + nz(a.Allocation_Type__c) + (a.Allocation_Status__c != null ? ', ' + a.Allocation_Status__c : '') + ')_'
            + (o != null && o.StageName != null ? ' · stage ' + o.StageName : '')
            + (o != null && o.Probability != null ? ' · ' + String.valueOf(Integer.valueOf(o.Probability)) + '%' : '')
            + (restr != null ? ' · restriction ' + restr : '')
            + ' · gift commitment ' + (gc ? 'linked' : '_not linked_')
            + (o != null && String.isNotBlank(o.Guardian__c) ? ' · owner ' + o.Guardian__c : '');
    }

    /* ---------------- Opportunity direction: where this grant is allocated ---------------- */

    private static String opportunitySummary(FundingContext fc) {
        String iso = fc.currencyIsoCode;
        Opportunity o = fc.focusOpportunity;
        Map<Id, Budget_Line__c> blById = new Map<Id, Budget_Line__c>();
        for (Budget_Line__c bl : fc.budgetLines) { blById.put(bl.Id, bl); }

        String head = '**Funding Lineage — ' + o.Name + '**'
            + (o.Account != null ? ' (' + o.Account.Name + ')' : '')
            + (o.Amount != null ? ' · opportunity amount ' + AmaizeFormat.money(o.Amount, iso) : '')
            + (o.StageName != null ? ' · stage ' + o.StageName : '');

        String body;
        if (fc.allocations.isEmpty()) {
            body = '\n\nThis grant has no funding allocations, so it is not yet tied to any Budget Line. '
                + 'Its opportunity amount is fundraising context only — it does not yet consume headroom anywhere.';
        } else {
            List<String> rows = new List<String>();
            Decimal totalAllocated = 0;
            for (Allocation__c a : fc.allocations) {
                Budget_Line__c bl = (a.Budget_Line__c != null) ? blById.get(a.Budget_Line__c) : null;
                totalAllocated += AmaizeBudgetHeadroom.nz(a.Funds_Allocated__c);
                rows.add('- ' + (bl != null ? '**' + HeadroomFormat.lineLabel(bl) + '**'
                                             : '**(allocation not linked to a Budget Line)**')
                    + ': ' + AmaizeFormat.money(a.Funds_Allocated__c, iso)
                    + ' _(' + nz(a.Allocation_Type__c)
                    + (a.Allocation_Status__c != null ? ', ' + a.Allocation_Status__c : '') + ')_');
            }
            body = '\n\n**Allocated across ' + fc.allocations.size() + ' allocation'
                + (fc.allocations.size() == 1 ? '' : 's') + ' totalling ' + AmaizeFormat.money(totalAllocated, iso)
                + '** (allocation amounts are the Budget Line exposure — not the full opportunity amount):\n'
                + String.join(rows, '\n');
        }
        return head + body + dataQuality(fc)
            + '\n\n_Ask "are any grants competing for" one of these budget lines to see the competition view._';
    }

    /* ---------------- shared ---------------- */

    private static String dataQuality(FundingContext fc) {
        List<String> notes = new List<String>();
        if (fc.allocationsMissingGiftCommitment > 0) {
            notes.add(fc.allocationsMissingGiftCommitment + ' allocation'
                + (fc.allocationsMissingGiftCommitment == 1 ? '' : 's') + ' have no linked Gift Commitment');
        }
        if (fc.allocationsMissingRestriction > 0) {
            notes.add(fc.allocationsMissingRestriction + ' allocation'
                + (fc.allocationsMissingRestriction == 1 ? '' : 's') + ' have no linked Restriction');
        }
        if (fc.allocationsUnlinkedToBudgetLine > 0) {
            notes.add(fc.allocationsUnlinkedToBudgetLine + ' allocation'
                + (fc.allocationsUnlinkedToBudgetLine == 1 ? '' : 's') + ' are not tied to a Budget Line');
        }
        if (fc.viaMatchKey) {
            notes.add('some allocations are linked to the Budget Line by matching key rather than a direct lookup');
        }
        return notes.isEmpty() ? '' : '\n\n**Data Quality Notes** — ' + HeadroomFormat.humanJoin(notes) + '.';
    }

    private static String nextStep(FundingContext fc) {
        if (fc.severity != null && (fc.severity.startsWith('High') || fc.severity.startsWith('Critical'))) {
            return '\n\n**Recommended Next Step** — Review the competing pipeline allocations with Grants '
                + 'Finance and the opportunity owners before these proposals progress further.';
        }
        return '';
    }

    private static Opportunity opp(Allocation__c a) {
        if (a.Restriction__r != null && a.Restriction__r.Gift_Commitment__r != null) {
            return a.Restriction__r.Gift_Commitment__r.Opportunity;
        }
        return null;
    }

    private static String nz(String s) { return String.isBlank(s) ? '—' : s; }

    private static String json(FundingContext fc) {
        return JSON.serialize(new Map<String, Object>{
            'direction' => fc.direction,
            'status' => String.valueOf(fc.status),
            'budgetLineCount' => fc.budgetLines.size(),
            'allocationCount' => fc.allocations.size(),
            'securedHeadroom' => fc.securedHeadroom,
            'combinedCompeting' => fc.combinedCompeting,
            'potentialExcess' => fc.potentialExcess,
            'severity' => fc.severity
        });
    }
}
