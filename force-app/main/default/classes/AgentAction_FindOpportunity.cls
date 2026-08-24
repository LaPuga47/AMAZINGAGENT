/**
 * Agent Action: Find Opportunity. Thin invocable wrapper — maps request/response
 * DTOs to OpportunityService. Contains NO SOQL and NO business logic. Gated by a
 * feature flag; every invocation is logged; errors return a safe message.
 */
public with sharing class AgentAction_FindOpportunity {
    @TestVisible
    private static final String ACTION_NAME = 'AgentAction_FindOpportunity';

    @TestVisible
    private static IOpportunityService service = new OpportunityService();

    @InvocableMethod(
        label='Find Opportunity'
        description='Search grant and fundraising opportunities by name, account, and/or stage. Read-only.'
        category='OAF Employee Agent'
    )
    public static List<Response> findOpportunity(List<Request> requests) {
        List<Response> responses = new List<Response>();
        for (Request request : requests) {
            responses.add(handle(request));
        }
        return responses;
    }

    private static Response handle(Request request) {
        Long startMs = System.currentTimeMillis();
        try {
            if (!FeatureFlag.isEnabled(ACTION_NAME)) {
                return toResponse(ResponseBuilder.error('The Find Opportunity action is currently disabled.'), null);
            }

            Id accountId = null;
            if (String.isNotBlank(request.accountId)) {
                ValidationUtils.require(
                    ValidationUtils.isValidId(request.accountId),
                    'The provided Account Id is not a valid Salesforce Id.'
                );
                accountId = (Id) request.accountId;
            }

            List<OpportunitySummary> results = service.findOpportunities(
                request.searchTerm,
                accountId,
                request.stage,
                request.maxResults
            );

            SearchResult envelope = results.isEmpty()
                ? ResponseBuilder.empty('No opportunities matched your search.')
                : ResponseBuilder.success(results.size());

            Logger.action(ACTION_NAME, envelope.message, System.currentTimeMillis() - startMs);
            return toResponse(envelope, results);
        } catch (AppException ae) {
            Logger.error(ACTION_NAME, ae.getMessage());
            return toResponse(ResponseBuilder.error(ae.getMessage()), null);
        } catch (Exception e) {
            Logger.error(ACTION_NAME, e.getMessage());
            return toResponse(ResponseBuilder.error('Something went wrong while searching opportunities.'), null);
        }
    }

    private static Response toResponse(SearchResult envelope, List<OpportunitySummary> results) {
        Response response = new Response();
        response.success = envelope.success;
        response.message = envelope.message;
        response.count = envelope.count;
        response.opportunities = results == null ? new List<OpportunitySummary>() : results;
        List<AgentRecordResult> refs = new List<AgentRecordResult>();
        if (results != null) {
            for (OpportunitySummary s : results) {
                if (s.record != null) {
                    refs.add(s.record);
                }
            }
        }
        response.records = refs;
        response.resultsText = buildResultsText(results);
        return response;
    }

    /** Human-readable summary the agent can surface directly. */
    private static String buildResultsText(List<OpportunitySummary> results) {
        if (results == null || results.isEmpty()) {
            return '';
        }
        List<String> lines = new List<String>();
        for (OpportunitySummary s : results) {
            String line = s.name + ' — Stage: ' + (String.isBlank(s.stage) ? 'N/A' : s.stage);
            if (String.isNotBlank(s.formattedAmount)) {
                line += ', Amount: ' + s.formattedAmount;
            }
            if (s.closeDate != null) {
                line += ', Close Date: ' + FormatUtils.formatDate(s.closeDate);
            }
            if (String.isNotBlank(s.accountName)) {
                line += ', Account: ' + s.accountName;
            }
            lines.add(line);
        }
        return SummaryText.sanitize(String.join(lines, '\n'));
    }

    public class Request {
        @InvocableVariable(label='Search Term' description='Full or partial opportunity name.' required=false)
        public String searchTerm;
        @InvocableVariable(label='Account Id' description='Restrict results to this Account Id.' required=false)
        public String accountId;
        @InvocableVariable(label='Stage' description='Restrict results to this opportunity stage.' required=false)
        public String stage;
        @InvocableVariable(label='Max Results' description='Max records to return (default 10, max 50).' required=false)
        public Integer maxResults;
    }

    public class Response {
        @InvocableVariable(label='Success' description='Whether the search ran successfully.')
        public Boolean success;
        @InvocableVariable(label='Message' description='Human-readable status message.')
        public String message;
        @InvocableVariable(label='Count' description='Number of opportunities returned.')
        public Integer count;
        @InvocableVariable(label='Results Text' description='Human-readable summary of the matching opportunities.')
        public String resultsText;
        @InvocableVariable(label='Opportunities' description='Matching opportunities.')
        public List<OpportunitySummary> opportunities;
        @InvocableVariable(label='Records' description='Clickable record cards for the matching records.')
        public List<AgentRecordResult> records;
    }
}