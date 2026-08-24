/**
 * Agent Action: Find Gift Transaction. Thin invocable wrapper — maps request/
 * response DTOs to GiftTransactionService. Contains NO SOQL and NO business logic.
 * Gated by a feature flag; every invocation is logged; errors return a safe message.
 */
public with sharing class AgentAction_FindGiftTransaction {
    @TestVisible
    private static final String ACTION_NAME = 'AgentAction_FindGiftTransaction';

    @TestVisible
    private static IGiftTransactionService service = new GiftTransactionService();

    @InvocableMethod(
        label='Find Gift Transaction'
        description='Search Gift Transactions (payments) by name, donor, gift commitment, and/or status. Read-only.'
        category='OAF Employee Agent'
    )
    public static List<Response> findGiftTransaction(List<Request> requests) {
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
                return toResponse(ResponseBuilder.error('The Find Gift Transaction action is currently disabled.'), null);
            }

            Id donorId = null;
            if (String.isNotBlank(request.donorId)) {
                ValidationUtils.require(
                    ValidationUtils.isValidId(request.donorId),
                    'The provided Donor Id is not a valid Salesforce Id.'
                );
                donorId = (Id) request.donorId;
            }

            Id giftCommitmentId = null;
            if (String.isNotBlank(request.giftCommitmentId)) {
                ValidationUtils.require(
                    ValidationUtils.isValidId(request.giftCommitmentId),
                    'The provided Gift Commitment Id is not a valid Salesforce Id.'
                );
                giftCommitmentId = (Id) request.giftCommitmentId;
            }

            Id campaignId = null;
            if (String.isNotBlank(request.campaignId)) {
                ValidationUtils.require(
                    ValidationUtils.isValidId(request.campaignId),
                    'The provided Campaign Id is not a valid Salesforce Id.'
                );
                campaignId = (Id) request.campaignId;
            }

            List<GiftTransactionSummary> results = service.findGiftTransactions(
                request.searchTerm,
                donorId,
                giftCommitmentId,
                campaignId,
                request.status,
                request.maxResults
            );

            SearchResult envelope = results.isEmpty()
                ? ResponseBuilder.empty('No gift transactions matched your search.')
                : ResponseBuilder.success(results.size());

            Logger.action(ACTION_NAME, envelope.message, System.currentTimeMillis() - startMs);
            return toResponse(envelope, results);
        } catch (AppException ae) {
            Logger.error(ACTION_NAME, ae.getMessage());
            return toResponse(ResponseBuilder.error(ae.getMessage()), null);
        } catch (Exception e) {
            Logger.error(ACTION_NAME, e.getMessage());
            return toResponse(ResponseBuilder.error('Something went wrong while searching gift transactions.'), null);
        }
    }

    private static Response toResponse(SearchResult envelope, List<GiftTransactionSummary> results) {
        Response response = new Response();
        response.success = envelope.success;
        response.message = envelope.message;
        response.count = envelope.count;
        response.giftTransactions = results == null ? new List<GiftTransactionSummary>() : results;
        List<AgentRecordResult> refs = new List<AgentRecordResult>();
        if (results != null) {
            for (GiftTransactionSummary s : results) {
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
    private static String buildResultsText(List<GiftTransactionSummary> results) {
        if (results == null || results.isEmpty()) {
            return '';
        }
        List<String> lines = new List<String>();
        for (GiftTransactionSummary s : results) {
            String line = s.name;
            if (String.isNotBlank(s.donorName)) { line += ' — Donor: ' + s.donorName; }
            if (String.isNotBlank(s.formattedAmount)) { line += ', Amount: ' + s.formattedAmount; }
            if (s.transactionDate != null) { line += ', Date: ' + FormatUtils.formatDate(s.transactionDate); }
            if (String.isNotBlank(s.status)) { line += ', Status: ' + s.status; }
            if (String.isNotBlank(s.paymentMethod)) { line += ', Payment: ' + s.paymentMethod; }
            if (String.isNotBlank(s.giftType)) { line += ', Gift Type: ' + s.giftType; }
            if (String.isNotBlank(s.giftCommitmentName)) { line += ', Commitment: ' + s.giftCommitmentName; }
            if (String.isNotBlank(s.campaignName)) { line += ', Campaign: ' + s.campaignName; }
            lines.add(line);
        }
        return SummaryText.sanitize(String.join(lines, '\n'));
    }

    public class Request {
        @InvocableVariable(label='Search Term' description='Full or partial gift transaction name.' required=false)
        public String searchTerm;
        @InvocableVariable(label='Donor Id' description='Restrict results to this donor Account Id.' required=false)
        public String donorId;
        @InvocableVariable(label='Gift Commitment Id' description='Restrict results to this Gift Commitment Id.' required=false)
        public String giftCommitmentId;
        @InvocableVariable(label='Campaign Id' description='Restrict results to gift transactions attributed to this Campaign Id.' required=false)
        public String campaignId;
        @InvocableVariable(label='Status' description='Restrict results to this transaction status.' required=false)
        public String status;
        @InvocableVariable(label='Max Results' description='Max records to return (default 10, max 50).' required=false)
        public Integer maxResults;
    }

    public class Response {
        @InvocableVariable(label='Success' description='Whether the search ran successfully.')
        public Boolean success;
        @InvocableVariable(label='Message' description='Human-readable status message.')
        public String message;
        @InvocableVariable(label='Count' description='Number of gift transactions returned.')
        public Integer count;
        @InvocableVariable(label='Results Text' description='Human-readable summary of the matching gift transactions.')
        public String resultsText;
        @InvocableVariable(label='Gift Transactions' description='Matching gift transactions.')
        public List<GiftTransactionSummary> giftTransactions;
        @InvocableVariable(label='Records' description='Clickable record cards for the matching records.')
        public List<AgentRecordResult> records;
    }
}