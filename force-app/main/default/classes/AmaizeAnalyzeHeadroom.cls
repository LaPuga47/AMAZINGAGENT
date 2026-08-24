/**
 * AmaizeAnalyzeHeadroom — the single-Budget-Line headroom action for the Headroom
 * Analysis subagent.
 *
 * Given the identifying dimensions (fiscal year, country, business unit, and optionally
 * sub-unit, department, cost type, cost category), it identifies exactly one Budget Line
 * and reports its budget, secured / likely / pipeline funding, and headroom — all read
 * from the Budget Line's own stored/calculated fields (Secured_Headroom__c /
 * Forecast_Headroom__c / Headroom_status__c), never recomputed or invented.
 *
 * When a specific line can't be pinned down it says so honestly:
 *   - NEEDS_INFO : asks for the missing required dimension(s).
 *   - AMBIGUOUS  : lists how the matching Budget Lines differ and asks the user to pick.
 *   - NOT_FOUND  : reports no matching Budget Line and which dimensions were used.
 *
 * Read-only. Scalar String/Boolean I/O per Agentforce platform rules.
 */
public with sharing class AmaizeAnalyzeHeadroom {

    /* ---------------- Action input ---------------- */
    public class Request {
        @InvocableVariable(label='Country' description='Country of the Budget Line, e.g. Kenya' required=true)
        public String country;

        @InvocableVariable(label='Business Unit' description='Salesforce Business Unit / program, e.g. Core Program' required=true)
        public String businessUnit;

        @InvocableVariable(label='Fiscal Year' description='Fiscal year, e.g. 2027' required=false)
        public Integer fiscalYear;

        @InvocableVariable(label='Sub-Unit' description='Salesforce Sub-Unit. Use "N/A" when the Budget Line has no sub-unit.' required=false)
        public String subUnit;

        @InvocableVariable(label='Department' description='Salesforce Department. Use "N/A" when not applicable.' required=false)
        public String department;

        @InvocableVariable(label='Cost Type' description='Salesforce Cost Type. Use "N/A" when not applicable.' required=false)
        public String costType;

        @InvocableVariable(label='Cost Category' description='Salesforce Cost Category. Use "N/A" when not applicable.' required=false)
        public String costCategory;
    }

    /* ---------------- Action output ---------------- */
    public class Result {
        @InvocableVariable(label='Summary' description='Human-readable headroom answer, clarification, or "not found" message to show the user.')
        public String summary;

        @InvocableVariable(label='Signal' description='Headroom status when found (Headroom Available / Some Headroom Available / Headroom Unavailable), otherwise NEEDS_INFO, AMBIGUOUS, or NOT_FOUND.')
        public String signal;

        @InvocableVariable(label='Headroom JSON' description='Machine-readable headroom detail for the identified Budget Line.')
        public String headroomJson;

        @InvocableVariable(label='Found' description='True only when exactly one Budget Line was identified.')
        public Boolean found;
    }

    @InvocableMethod(
        label='Analyze Budget Line Headroom'
        description='Identifies a single Budget Line from its dimensions and reports its budget, secured/likely/pipeline funding and headroom. Asks for missing or ambiguous dimensions instead of guessing.')
    public static List<Result> analyze(List<Request> requests) {
        List<Result> results = new List<Result>();
        // Agentforce invokes an action with a single request; we still loop defensively.
        // Each analyze() call is self-contained; there is no DML anywhere in this path.
        HeadroomService service = new HeadroomService();
        for (Request req : requests) {
            results.add(answerOne(req, service));
        }
        return results;
    }

    private static Result answerOne(Request req, HeadroomService service) {
        BudgetLineDimensions dims = new BudgetLineDimensions();
        dims.country = req.country;
        dims.businessUnit = req.businessUnit;
        dims.fiscalYear = (req.fiscalYear != null) ? String.valueOf(req.fiscalYear) : null;
        dims.subUnit = req.subUnit;
        dims.department = req.department;
        dims.costType = req.costType;
        dims.costCategory = req.costCategory;

        HeadroomAnalysis a = service.analyze(dims);

        Result r = new Result();
        switch on a.status {
            when FOUND {
                r.found = true;
                r.signal = a.line.Headroom_status__c;
                r.summary = foundSummary(a);
                r.headroomJson = foundJson(a);
            }
            when AMBIGUOUS {
                r.found = false;
                r.signal = 'AMBIGUOUS';
                r.summary = ambiguousSummary(a);
                r.headroomJson = '{"found":false,"status":"AMBIGUOUS","matchCount":' + a.candidates.size() + '}';
            }
            when NEEDS_INFO {
                r.found = false;
                r.signal = 'NEEDS_INFO';
                r.summary = needsInfoSummary(a);
                r.headroomJson = '{"found":false,"status":"NEEDS_INFO"}';
            }
            when else { // NOT_FOUND
                r.found = false;
                r.signal = 'NOT_FOUND';
                r.summary = notFoundSummary(a);
                r.headroomJson = '{"found":false,"status":"NOT_FOUND"}';
            }
        }
        return r;
    }

    /* ---------------- Summary composition ---------------- */

    private static String foundSummary(HeadroomAnalysis a) {
        Budget_Line__c bl = a.line;
        String iso = bl.CurrencyIsoCode;
        Decimal budget = AmaizeBudgetHeadroom.budgetCost(bl.Budget_Amount__c);
        Decimal secured = AmaizeBudgetHeadroom.nz(bl.Secured_Funding__c);
        Decimal likely = AmaizeBudgetHeadroom.nz(bl.Likely_Funding__c);
        Decimal pipeline = AmaizeBudgetHeadroom.nz(bl.Pipeline_Funding__c);
        Decimal forecastHeadroom = AmaizeBudgetHeadroom.nz(bl.Forecast_Headroom__c);
        Decimal securedHeadroom = AmaizeBudgetHeadroom.nz(bl.Secured_Headroom__c);

        String label = HeadroomFormat.lineLabel(bl);
        String funding = 'Secured funding is ' + AmaizeFormat.money(secured, iso)
            + ', likely funding is ' + AmaizeFormat.money(likely, iso)
            + ', and pipeline funding is ' + AmaizeFormat.money(pipeline, iso);

        String body;
        String recommendation;
        if (forecastHeadroom < 0) {
            // Negative headroom is valid: over-allocation, not an error.
            body = label + ' has a budget of ' + AmaizeFormat.money(budget, iso) + '. ' + funding + '. '
                + 'This Budget Line is currently over-allocated by ' + AmaizeFormat.money(-forecastHeadroom, iso)
                + ' based on secured, likely, and pipeline funding.';
            recommendation = '**Recommendation:** Don\'t raise more here — confirm with Grants Finance.';
        } else {
            body = label + ' has a budget of ' + AmaizeFormat.money(budget, iso) + '. ' + funding
                + ', leaving ' + AmaizeFormat.money(forecastHeadroom, iso) + ' in headroom. '
                + 'Secured headroom (budget minus secured funding only) is '
                + AmaizeFormat.money(securedHeadroom, iso) + '.';
            if (bl.Headroom_status__c == 'Headroom Available') {
                recommendation = '**Recommendation:** There\'s room to raise here.';
            } else {
                recommendation = '**Recommendation:** Room is tight — confirm with Grants Finance before pitching.';
            }
        }

        // Grounding note about where the allocation detail came from (or that there is none).
        String allocNote;
        if (a.allocationSource == 'none' || a.allocations == null || a.allocations.totalCount == 0) {
            allocNote = '\n\n_No allocations are currently linked to this Budget Line; the figures above are the Budget Line\'s stored funding._';
        } else {
            allocNote = '\n\n_Based on ' + a.allocations.totalCount + ' allocation'
                + (a.allocations.totalCount == 1 ? '' : 's') + ' on this Budget Line'
                + (String.isNotBlank(a.allocations.topGrantName)
                    ? ', the largest being ' + a.allocations.topGrantName : '') + '._';
        }

        return body + '\n\n' + recommendation + allocNote;
    }

    private static String ambiguousSummary(HeadroomAnalysis a) {
        Integer n = a.candidates.size();
        String diff = (a.distinguishingDimensions != null && !a.distinguishingDimensions.isEmpty())
            ? ' They differ by ' + String.join(a.distinguishingDimensions, '; ') + '.'
            : '';
        String ask = a.subUnitMissing
            ? ' Which one should I use? If the Budget Line has no sub-unit, you can specify N/A.'
            : ' Which one should I use?';
        return 'I found ' + n + ' Budget Lines matching the information provided.' + diff + ask;
    }

    private static String needsInfoSummary(HeadroomAnalysis a) {
        String missing = HeadroomFormat.humanJoin(a.missingDimensions);
        String base = 'I can check that. I still need the ' + missing + '.';
        if (a.subUnitMissing) {
            base += ' Please also give the sub-unit — if there is no applicable sub-unit, specify N/A.';
        }
        return base;
    }

    private static String notFoundSummary(HeadroomAnalysis a) {
        String used = HeadroomFormat.humanJoin(a.requested.suppliedPhrases());
        return 'I couldn\'t find a Budget Line matching ' + used + '. '
            + 'I won\'t estimate headroom without a matching Budget Line — '
            + 'please double-check those values, or ask Grants Finance whether this Budget Line exists.';
    }

    private static String foundJson(HeadroomAnalysis a) {
        Budget_Line__c bl = a.line;
        Map<String, Object> j = new Map<String, Object>{
            'found' => true,
            'status' => bl.Headroom_status__c,
            'fiscalYear' => bl.Fiscal_Year__c,
            'country' => bl.Country__c,
            'businessUnit' => bl.BusinessUnit__c,
            'subUnit' => bl.Sub__c,
            'department' => bl.Department__c,
            'costType' => bl.Cost_Type__c,
            'costCategory' => bl.Cost_Category__c,
            'currency' => bl.CurrencyIsoCode,
            'budget' => AmaizeBudgetHeadroom.budgetCost(bl.Budget_Amount__c),
            'securedFunding' => AmaizeBudgetHeadroom.nz(bl.Secured_Funding__c),
            'likelyFunding' => AmaizeBudgetHeadroom.nz(bl.Likely_Funding__c),
            'pipelineFunding' => AmaizeBudgetHeadroom.nz(bl.Pipeline_Funding__c),
            'securedHeadroom' => AmaizeBudgetHeadroom.nz(bl.Secured_Headroom__c),
            'forecastHeadroom' => AmaizeBudgetHeadroom.nz(bl.Forecast_Headroom__c),
            'allocationSource' => a.allocationSource,
            'allocationCount' => (a.allocations == null ? 0 : a.allocations.totalCount)
        };
        return JSON.serialize(j);
    }
}
