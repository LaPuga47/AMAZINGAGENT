/**
 * Agent Action: Find Account. Thin invocable wrapper — maps request/response
 * DTOs to AccountService. Contains NO SOQL and NO business logic. Gated by a
 * feature flag; every invocation is logged; errors return a safe message.
 */
public with sharing class AgentAction_FindAccount {
    @TestVisible
    private static final String ACTION_NAME = 'AgentAction_FindAccount';

    @TestVisible
    private static IAccountService service = new AccountService();

    @InvocableMethod(
        label='Find Account'
        description='Search Accounts (organizations and donors) by name and/or type. Read-only.'
        category='OAF Employee Agent'
    )
    public static List<Response> findAccount(List<Request> requests) {
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
                return toResponse(ResponseBuilder.error('The Find Account action is currently disabled.'), null);
            }

            List<AccountSummary> results = service.findAccounts(
                request.searchTerm,
                request.accountType,
                request.maxResults
            );

            SearchResult envelope = results.isEmpty()
                ? ResponseBuilder.empty('No accounts matched your search.')
                : ResponseBuilder.success(results.size());

            Logger.action(ACTION_NAME, envelope.message, System.currentTimeMillis() - startMs);
            return toResponse(envelope, results);
        } catch (AppException ae) {
            Logger.error(ACTION_NAME, ae.getMessage());
            return toResponse(ResponseBuilder.error(ae.getMessage()), null);
        } catch (Exception e) {
            Logger.error(ACTION_NAME, e.getMessage());
            return toResponse(ResponseBuilder.error('Something went wrong while searching accounts.'), null);
        }
    }

    private static Response toResponse(SearchResult envelope, List<AccountSummary> results) {
        Response response = new Response();
        response.success = envelope.success;
        response.message = envelope.message;
        response.count = envelope.count;
        response.accounts = results == null ? new List<AccountSummary>() : results;
        List<AgentRecordResult> refs = new List<AgentRecordResult>();
        if (results != null) {
            for (AccountSummary s : results) {
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
    private static String buildResultsText(List<AccountSummary> results) {
        if (results == null || results.isEmpty()) {
            return '';
        }
        List<String> lines = new List<String>();
        for (AccountSummary s : results) {
            String line = s.name;
            if (String.isNotBlank(s.type)) { line += ' — Type: ' + s.type; }
            if (String.isNotBlank(s.industry)) { line += ', Industry: ' + s.industry; }
            if (String.isNotBlank(s.city)) { line += ', City: ' + s.city; }
            if (String.isNotBlank(s.country)) { line += ', Country: ' + s.country; }
            if (String.isNotBlank(s.phone)) { line += ', Phone: ' + s.phone; }
            if (String.isNotBlank(s.ownerName)) { line += ', Owner: ' + s.ownerName; }
            lines.add(line);
        }
        return SummaryText.sanitize(String.join(lines, '\n'));
    }

    public class Request {
        @InvocableVariable(label='Search Term' description='Full or partial account/donor name.' required=false)
        public String searchTerm;
        @InvocableVariable(label='Account Type' description='Restrict results to this Account Type.' required=false)
        public String accountType;
        @InvocableVariable(label='Max Results' description='Max records to return (default 10, max 50).' required=false)
        public Integer maxResults;
    }

    public class Response {
        @InvocableVariable(label='Success' description='Whether the search ran successfully.')
        public Boolean success;
        @InvocableVariable(label='Message' description='Human-readable status message.')
        public String message;
        @InvocableVariable(label='Count' description='Number of accounts returned.')
        public Integer count;
        @InvocableVariable(label='Results Text' description='Human-readable summary of the matching accounts.')
        public String resultsText;
        @InvocableVariable(label='Accounts' description='Matching accounts.')
        public List<AccountSummary> accounts;
        @InvocableVariable(label='Records' description='Clickable record cards for the matching records.')
        public List<AgentRecordResult> records;
    }
}