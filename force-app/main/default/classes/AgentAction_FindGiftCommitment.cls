/**
 * Agent Action: Find Gift Commitment. Thin invocable wrapper — maps request/
 * response DTOs to GiftCommitmentService. Contains NO SOQL and NO business logic.
 * Gated by a feature flag; every invocation is logged; errors return a safe message.
 */
public with sharing class AgentAction_FindGiftCommitment {
    @TestVisible
    private static final String ACTION_NAME = 'AgentAction_FindGiftCommitment';

    @TestVisible
    private static IGiftCommitmentService service = new GiftCommitmentService();

    @InvocableMethod(
        label='Find Gift Commitment'
        description='Search Gift Commitments (pledges) by name, donor, and/or status. Read-only.'
        category='OAF Employee Agent'
    )
    public static List<Response> findGiftCommitment(List<Request> requests) {
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
                return toResponse(ResponseBuilder.error('The Find Gift Commitment action is currently disabled.'), null);
            }

            Id donorId = null;
            if (String.isNotBlank(request.donorId)) {
                ValidationUtils.require(
                    ValidationUtils.isValidId(request.donorId),
                    'The provided Donor Id is not a valid Salesforce Id.'
                );
                donorId = (Id) request.donorId;
            }

            List<GiftCommitmentSummary> results = service.findGiftCommitments(
                request.searchTerm,
                donorId,
                request.status,
                request.maxResults
            );

            SearchResult envelope = results.isEmpty()
                ? ResponseBuilder.empty('No gift commitments matched your search.')
                : ResponseBuilder.success(results.size());

            Logger.action(ACTION_NAME, envelope.message, System.currentTimeMillis() - startMs);
            return toResponse(envelope, results);
        } catch (AppException ae) {
            Logger.error(ACTION_NAME, ae.getMessage());
            return toResponse(ResponseBuilder.error(ae.getMessage()), null);
        } catch (Exception e) {
            Logger.error(ACTION_NAME, e.getMessage());
            return toResponse(ResponseBuilder.error('Something went wrong while searching gift commitments.'), null);
        }
    }

    private static Response toResponse(SearchResult envelope, List<GiftCommitmentSummary> results) {
        Response response = new Response();
        response.success = envelope.success;
        response.message = envelope.message;
        response.count = envelope.count;
        response.giftCommitments = results == null ? new List<GiftCommitmentSummary>() : results;
        List<AgentRecordResult> refs = new List<AgentRecordResult>();
        if (results != null) {
            for (GiftCommitmentSummary s : results) {
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
    private static String buildResultsText(List<GiftCommitmentSummary> results) {
        if (results == null || results.isEmpty()) {
            return '';
        }
        List<String> lines = new List<String>();
        for (GiftCommitmentSummary s : results) {
            String line = s.name;
            if (String.isNotBlank(s.donorName)) { line += ' — Donor: ' + s.donorName; }
            if (String.isNotBlank(s.status)) { line += ', Status: ' + s.status; }
            if (String.isNotBlank(s.formattedExpectedTotal)) { line += ', Expected Total: ' + s.formattedExpectedTotal; }
            if (s.totalPaidAmount != null) { line += ', Paid: ' + FormatUtils.formatAmount(s.totalPaidAmount); }
            if (s.remainingBalance != null) { line += ', Remaining: ' + FormatUtils.formatAmount(s.remainingBalance); }
            if (s.nextTransactionDate != null) { line += ', Next Payment: ' + FormatUtils.formatDate(s.nextTransactionDate); }
            if (s.nextTransactionAmount != null) { line += ' (' + FormatUtils.formatAmount(s.nextTransactionAmount) + ')'; }
            lines.add(line);
        }
        return SummaryText.sanitize(String.join(lines, '\n'));
    }

    public class Request {
        @InvocableVariable(label='Search Term' description='Full or partial gift commitment name.' required=false)
        public String searchTerm;
        @InvocableVariable(label='Donor Id' description='Restrict results to this donor Account Id.' required=false)
        public String donorId;
        @InvocableVariable(label='Status' description='Restrict results to this commitment status.' required=false)
        public String status;
        @InvocableVariable(label='Max Results' description='Max records to return (default 10, max 50).' required=false)
        public Integer maxResults;
    }

    public class Response {
        @InvocableVariable(label='Success' description='Whether the search ran successfully.')
        public Boolean success;
        @InvocableVariable(label='Message' description='Human-readable status message.')
        public String message;
        @InvocableVariable(label='Count' description='Number of gift commitments returned.')
        public Integer count;
        @InvocableVariable(label='Results Text' description='Human-readable summary of the matching gift commitments.')
        public String resultsText;
        @InvocableVariable(label='Gift Commitments' description='Matching gift commitments.')
        public List<GiftCommitmentSummary> giftCommitments;
        @InvocableVariable(label='Records' description='Clickable record cards for the matching records.')
        public List<AgentRecordResult> records;
    }
}