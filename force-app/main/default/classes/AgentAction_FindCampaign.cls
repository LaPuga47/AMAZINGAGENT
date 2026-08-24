/**
 * Agent Action: Find Campaign. Thin invocable wrapper — maps request/response
 * DTOs to CampaignService. Contains NO SOQL and NO business logic. Gated by a
 * feature flag; every invocation is logged; errors return a safe message.
 */
public with sharing class AgentAction_FindCampaign {
    @TestVisible
    private static final String ACTION_NAME = 'AgentAction_FindCampaign';

    @TestVisible
    private static ICampaignService service = new CampaignService();

    @InvocableMethod(
        label='Find Campaign'
        description='Search Campaigns by name and/or status. Read-only.'
        category='OAF Employee Agent'
    )
    public static List<Response> findCampaign(List<Request> requests) {
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
                return toResponse(ResponseBuilder.error('The Find Campaign action is currently disabled.'), null);
            }

            List<CampaignSummary> results = service.findCampaigns(
                request.searchTerm,
                request.status,
                request.maxResults
            );

            SearchResult envelope = results.isEmpty()
                ? ResponseBuilder.empty('No campaigns matched your search.')
                : ResponseBuilder.success(results.size());

            Logger.action(ACTION_NAME, envelope.message, System.currentTimeMillis() - startMs);
            return toResponse(envelope, results);
        } catch (AppException ae) {
            Logger.error(ACTION_NAME, ae.getMessage());
            return toResponse(ResponseBuilder.error(ae.getMessage()), null);
        } catch (Exception e) {
            Logger.error(ACTION_NAME, e.getMessage());
            return toResponse(ResponseBuilder.error('Something went wrong while searching campaigns.'), null);
        }
    }

    private static Response toResponse(SearchResult envelope, List<CampaignSummary> results) {
        Response response = new Response();
        response.success = envelope.success;
        response.message = envelope.message;
        response.count = envelope.count;
        response.campaigns = results == null ? new List<CampaignSummary>() : results;
        List<AgentRecordResult> refs = new List<AgentRecordResult>();
        if (results != null) {
            for (CampaignSummary s : results) {
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
    private static String buildResultsText(List<CampaignSummary> results) {
        if (results == null || results.isEmpty()) {
            return '';
        }
        List<String> lines = new List<String>();
        for (CampaignSummary s : results) {
            String line = s.name;
            if (String.isNotBlank(s.type)) { line += ' — Type: ' + s.type; }
            if (String.isNotBlank(s.status)) { line += ', Status: ' + s.status; }
            if (s.startDate != null) { line += ', Start: ' + FormatUtils.formatDate(s.startDate); }
            if (s.endDate != null) { line += ', End: ' + FormatUtils.formatDate(s.endDate); }
            line += ', Active: ' + (s.isActive == true ? 'Yes' : 'No');
            if (String.isNotBlank(s.ownerName)) { line += ', Owner: ' + s.ownerName; }
            lines.add(line);
        }
        return SummaryText.sanitize(String.join(lines, '\n'));
    }

    public class Request {
        @InvocableVariable(label='Search Term' description='Full or partial campaign name.' required=false)
        public String searchTerm;
        @InvocableVariable(label='Status' description='Restrict results to this campaign status.' required=false)
        public String status;
        @InvocableVariable(label='Max Results' description='Max records to return (default 10, max 50).' required=false)
        public Integer maxResults;
    }

    public class Response {
        @InvocableVariable(label='Success' description='Whether the search ran successfully.')
        public Boolean success;
        @InvocableVariable(label='Message' description='Human-readable status message.')
        public String message;
        @InvocableVariable(label='Count' description='Number of campaigns returned.')
        public Integer count;
        @InvocableVariable(label='Results Text' description='Human-readable summary of the matching campaigns.')
        public String resultsText;
        @InvocableVariable(label='Campaigns' description='Matching campaigns.')
        public List<CampaignSummary> campaigns;
        @InvocableVariable(label='Records' description='Clickable record cards for the matching records.')
        public List<AgentRecordResult> records;
    }
}