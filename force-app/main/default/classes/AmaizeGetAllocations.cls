/**
 * AmaizeGetAllocations — Funding Allocation drill-down for the Competing Grants Analysis
 * subagent. When the user explicitly asks to see the underlying allocations behind a governed
 * Headroom scope, this returns the individual Allocation records — grouped by Opportunity,
 * split into Secured vs Likely/Pipeline — with clickable Allocation / Opportunity / Restriction
 * / Gift Commitment / Budget Line links.
 *
 * It REUSES CompetingGrantsService.analyze for retrieval (the same governed Budget Line
 * population and the same allocations the competing-grants view is built on), so figures
 * reconcile with that view. Read-only. Scalar I/O.
 */
public with sharing class AmaizeGetAllocations {

    // The Agentforce model keeps record links clickable only for short lists (it flattens longer
    // ones to plain text), so by default we show up to SHOW_CLICKABLE_MAX records WITH links and
    // offer "see all". When the user asks to see everything (showAll), we return the full list up
    // to HARD_CAP (accepting that 6+ rows may render as plain text) rather than truncate silently.
    private static final Integer SHOW_CLICKABLE_MAX = 5;
    private static final Integer HARD_CAP = 200;

    public class Request {
        @InvocableVariable(label='Program' description='Headroom category / program, e.g. Core Program, Rural Retail, Trees. Pass the user\'s wording; synonyms are resolved.' required=true)
        public String program;
        @InvocableVariable(label='Country' description='Country of the Budget Lines, e.g. Kenya. The authoritative filter.' required=true)
        public String country;
        @InvocableVariable(label='Fiscal Year' description='Fiscal year, e.g. 2027. Defaults to the current scenario when omitted.' required=false)
        public Integer fiscalYear;
        @InvocableVariable(label='Allocation Type' description='Optional filter: Secured, Likely, or Pipeline. Omit for all.' required=false)
        public String allocationType;
        @InvocableVariable(label='Allocation Status' description='Optional filter: e.g. Approved or Pending. Omit for all.' required=false)
        public String allocationStatus;
        @InvocableVariable(label='Opportunity Name' description='Optional: limit the allocations to a single Opportunity by name.' required=false)
        public String opportunityName;
        @InvocableVariable(label='Show All' description='Set true when the user explicitly asks for the full list ("show all", "list every allocation"). Forces the complete list even beyond the summary threshold (still bounded by a response-size safety limit).' required=false)
        public Boolean showAll;
    }

    public class Result {
        @InvocableVariable(label='Summary' description='The grouped Funding Allocation drill-down to show the user.')
        public String summary;
        @InvocableVariable(label='Match Count' description='Total number of Funding Allocation records matched in this scope (before paging).')
        public Integer matchCount;
        @InvocableVariable(label='Results JSON' description='Machine-readable allocation records with deterministic record URLs.')
        public String resultsJson;
        @InvocableVariable(label='Found' description='True when the governed scope resolved to Budget Lines.')
        public Boolean found;
    }

    @InvocableMethod(
        label='Get Funding Allocations for Headroom Scope'
        description='Retrieves the individual Funding Allocation records for a governed Headroom scope (category + country + fiscal year), grouped by Opportunity and split into Secured vs Likely/Pipeline, with clickable record links. Use when the user explicitly asks to see the underlying allocations. Reuses the same governed population as competing-grants analysis.')
    public static List<Result> get(List<Request> requests) {
        List<Result> results = new List<Result>();
        CompetingGrantsService service = new CompetingGrantsService();
        for (Request req : requests) {
            results.add(answerOne(req, service));
        }
        return results;
    }

    private static Result answerOne(Request req, CompetingGrantsService service) {
        Result r = new Result();
        String fy = (req.fiscalYear != null) ? String.valueOf(req.fiscalYear) : null;
        CompetingGrantsResult a = service.analyze(req.program, req.country, fy);

        switch on a.status {
            when NONE {
                r.found = false; r.matchCount = 0;
                r.summary = 'No qualifying Budget Line records were found for ' + a.category + ' in '
                    + a.country + (a.fiscalYear != null ? ' in ' + a.fiscalYear : '')
                    + ', so there are no allocations to show.';
                r.resultsJson = '{"status":"NONE"}';
                return r;
            }
            when ZERO {
                r.found = false; r.matchCount = 0;
                r.summary = a.category + ' is defined as zero under the Headroom model, so it has no '
                    + 'Budget Lines and no allocations to list.';
                r.resultsJson = '{"status":"ZERO"}';
                return r;
            }
            when NOT_CONFIGURED {
                r.found = false; r.matchCount = 0;
                r.summary = 'The Headroom rule for "' + a.category + '" is not yet configured, '
                    + 'so I can\'t list its allocations.';
                r.resultsJson = '{"status":"NOT_CONFIGURED"}';
                return r;
            }
            when NEEDS_INFO {
                r.found = false; r.matchCount = 0;
                r.summary = 'I can list the allocations. I still need the ' + HeadroomFormat.humanJoin(a.missing) + '.';
                r.resultsJson = '{"status":"NEEDS_INFO"}';
                return r;
            }
            when else { /* FOUND — continue below */ }
        }

        r.found = true;
        String iso = a.currencyIsoCode;
        String scopeName = a.country + ' ' + a.category;
        String yr = a.fiscalYear != null ? a.fiscalYear : 'the current scenario';

        // Collect the scope allocations grouped by Opportunity, applying optional filters.
        String typeF = norm(req.allocationType);
        String statusF = norm(req.allocationStatus);
        String oppF = req.opportunityName == null ? null : req.opportunityName.trim().toLowerCase();

        List<CompetingGrant> secured = new List<CompetingGrant>();
        List<CompetingGrant> other = new List<CompetingGrant>();
        Integer total = 0;
        Decimal securedTotal = 0, otherTotal = 0;
        Set<Id> oppIds = new Set<Id>();

        for (CompetingGrant g : a.grants) {
            if (oppF != null && (g.opportunityName == null || !g.opportunityName.toLowerCase().contains(oppF))) { continue; }
            List<Allocation__c> securedAllocs = new List<Allocation__c>();
            List<Allocation__c> otherAllocs = new List<Allocation__c>();
            for (Allocation__c al : g.allocations) {
                String t = al.Allocation_Type__c;
                if (typeF != null && (t == null || t.toLowerCase() != typeF)) { continue; }
                if (statusF != null && (al.Allocation_Status__c == null || al.Allocation_Status__c.toLowerCase() != statusF)) { continue; }
                Decimal amt = AmaizeBudgetHeadroom.nz(al.Funds_Allocated__c);
                if (t == 'Secured') { securedAllocs.add(al); securedTotal += amt; } else { otherAllocs.add(al); otherTotal += amt; }
                total++;
                oppIds.add(g.opportunityId);
            }
            if (!securedAllocs.isEmpty()) { secured.add(subGrant(g, securedAllocs)); }
            if (!otherAllocs.isEmpty()) { other.add(subGrant(g, otherAllocs)); }
        }

        r.matchCount = total;

        if (total == 0) {
            r.summary = 'I found the ' + scopeName + ' Budget Lines for ' + yr + ', but no Funding '
                + 'Allocation records match'
                + (typeF != null || statusF != null || oppF != null ? ' those filters.' : ' them yet.');
            r.resultsJson = '{"status":"FOUND","allocationCount":0}';
            return r;
        }

        Boolean showAll = req.showAll == true;
        // Default keeps links clickable (short list); showAll returns the full list up to the safety cap.
        Integer maxRows = showAll ? HARD_CAP : SHOW_CLICKABLE_MAX;
        r.resultsJson = json(a, secured, other, iso);
        r.summary = render(scopeName, yr, iso, secured, other, total, oppIds.size(), maxRows, showAll);
        return r;
    }

    /** Grouped list, emitting up to maxRows records. Adds one closing line when the list is capped. */
    private static String render(String scopeName, String yr, String iso, List<CompetingGrant> secured,
            List<CompetingGrant> other, Integer total, Integer oppCount, Integer maxRows, Boolean showAll) {
        List<String> out = new List<String>();
        out.add(scopeName + ' has ' + total + ' Funding Allocation record' + (total == 1 ? '' : 's')
            + ' across ' + oppCount + ' Opportunit' + (oppCount == 1 ? 'y' : 'ies') + ' in ' + yr + '.');

        Integer[] cursor = new Integer[]{ 0 };
        String securedBlock = section('SECURED', secured, iso, cursor, maxRows);
        String otherBlock = section('LIKELY / PIPELINE', other, iso, cursor, maxRows);
        if (String.isNotBlank(securedBlock)) { out.add(securedBlock); }
        if (String.isNotBlank(otherBlock)) { out.add(otherBlock); }

        Integer shown = Math.min(total, maxRows);
        if (total > maxRows) {
            out.add(showAll
                ? '_Showing the first ' + shown + ' of ' + total + ' — the full list exceeds the response '
                    + 'size limit. Filter by Opportunity to see the rest._'
                : '_Showing ' + shown + ' of ' + total + ' with clickable links. Ask to see all ' + total
                    + ', or filter by Opportunity or Restriction._');
        } else {
            out.add('Would you like these summarized by Opportunity or Restriction?');
        }
        return String.join(out, '\n\n');
    }

    /** One section (Secured or Likely/Pipeline): opp headers + allocation lines, up to maxRows overall. */
    private static String section(String title, List<CompetingGrant> grants, String iso, Integer[] cursor, Integer maxRows) {
        List<String> blocks = new List<String>();
        for (CompetingGrant g : grants) {
            List<String> lines = new List<String>();
            for (Allocation__c al : g.allocations) {
                if (cursor[0] >= maxRows) { break; }
                cursor[0] = cursor[0] + 1;
                lines.add(allocLine(al, iso));
            }
            if (lines.isEmpty()) { continue; }
            // Plain (not bold) clickable Opportunity heading: the model preserves an inline link
            // but flattens a bold+link header, so keep it a bare link to stay clickable.
            String header = AmaizeLink.md(g.opportunityName, 'Opportunity', g.opportunityId);
            blocks.add(header + '\n' + String.join(lines, '\n'));
        }
        return blocks.isEmpty() ? '' : '**' + title + '**\n\n' + String.join(blocks, '\n\n');
    }

    /**
     * One allocation line, kept lean so the whole list stays short enough for the agent to
     * reproduce verbatim (long outputs get summarized, which flattens the links): Allocation
     * name, amount, status (only when populated), and its Restriction — all inline, all
     * clickable. The Allocation Type is conveyed by the SECTION heading, so it is not repeated
     * on each row; it (with Gift Commitment / Budget Line) stays in resultsJson for drill-down.
     */
    private static String allocLine(Allocation__c al, String iso) {
        String s = '- ' + AmaizeLink.md(al.Name, 'Allocation__c', al.Id)
            + ' — ' + AmaizeFormat.money(al.Funds_Allocated__c, iso);
        if (String.isNotBlank(al.Allocation_Status__c)) { s += ' | ' + al.Allocation_Status__c; }
        if (al.Restriction__c != null && al.Restriction__r != null) {
            s += ' | Restriction: ' + AmaizeLink.md(al.Restriction__r.Name, 'Restriction__c', al.Restriction__c);
        }
        return s;
    }

    /** A shallow copy of a grant carrying only the given (filtered) allocations. */
    private static CompetingGrant subGrant(CompetingGrant g, List<Allocation__c> allocs) {
        CompetingGrant c = new CompetingGrant();
        c.opportunityId = g.opportunityId;
        c.opportunityName = g.opportunityName;
        c.allocations = allocs;
        return c;
    }

    private static String json(CompetingGrantsResult a, List<CompetingGrant> secured, List<CompetingGrant> other, String iso) {
        List<Map<String, Object>> rows = new List<Map<String, Object>>();
        for (CompetingGrant g : dedupeUnion(secured, other)) {
            for (Allocation__c al : g.allocations) {
                Id gcId = (al.Restriction__r != null) ? al.Restriction__r.Gift_Commitment__c : null;
                rows.add(new Map<String, Object>{
                    'allocationId' => al.Id, 'allocationName' => al.Name,
                    'allocationUrl' => AmaizeLink.recordUrl('Allocation__c', al.Id),
                    'amount' => al.Funds_Allocated__c, 'allocationType' => al.Allocation_Type__c,
                    'allocationStatus' => al.Allocation_Status__c,
                    'opportunityId' => g.opportunityId, 'opportunityName' => g.opportunityName,
                    'opportunityUrl' => AmaizeLink.recordUrl('Opportunity', g.opportunityId),
                    'restrictionId' => al.Restriction__c, 'restrictionName' => (al.Restriction__r != null ? al.Restriction__r.Name : null),
                    'restrictionUrl' => AmaizeLink.recordUrl('Restriction__c', al.Restriction__c),
                    'giftCommitmentId' => gcId,
                    'giftCommitmentName' => (gcId != null ? al.Restriction__r.Gift_Commitment__r.Name : null),
                    'giftCommitmentUrl' => AmaizeLink.recordUrl('GiftCommitment', gcId),
                    'budgetLineId' => al.Budget_Line__c,
                    'budgetLineName' => (al.Budget_Line__r != null ? al.Budget_Line__r.Name : null),
                    'budgetLineUrl' => AmaizeLink.recordUrl('Budget_Line__c', al.Budget_Line__c),
                    'allocationDate' => al.Allocation_Date__c, 'probability' => al.Probability__c
                });
            }
        }
        return JSON.serialize(new Map<String, Object>{
            'category' => a.category, 'country' => a.country, 'fiscalYear' => a.fiscalYear,
            'budgetLineCount' => a.budgetLineCount, 'allocationCount' => rows.size(),
            'allocations' => rows
        });
    }

    /** Union of the secured + other sub-grants by Opportunity, merging their allocation lists. */
    private static List<CompetingGrant> dedupeUnion(List<CompetingGrant> secured, List<CompetingGrant> other) {
        Map<Id, CompetingGrant> byOpp = new Map<Id, CompetingGrant>();
        for (List<CompetingGrant> src : new List<List<CompetingGrant>>{ secured, other }) {
            for (CompetingGrant g : src) {
                CompetingGrant c = byOpp.get(g.opportunityId);
                if (c == null) { c = subGrant(g, new List<Allocation__c>()); byOpp.put(g.opportunityId, c); }
                c.allocations.addAll(g.allocations);
            }
        }
        return new List<CompetingGrant>(byOpp.values());
    }

    private static String norm(String v) { return String.isBlank(v) ? null : v.trim().toLowerCase(); }
    private static String nz(String v) { return String.isBlank(v) ? '—' : v; }
}
