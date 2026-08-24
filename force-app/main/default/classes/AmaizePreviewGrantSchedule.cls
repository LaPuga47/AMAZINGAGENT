/**
 * AmaizePreviewGrantSchedule — the read-only half of Step 3 (Generate Schedule).
 *
 * In plain terms: the RM describes a payment + reporting schedule (a total grant
 * amount, a list of disbursements, and a list of reports). The LLM packages those
 * details into a JSON string and passes it here. This action parses that JSON and
 * shows the RM a tidy preview table of the Gift Transactions and Grant Reports it
 * WOULD create — but it does not create anything. Creation only happens later, in
 * AmaizeCreateGrantSchedule, and only after the RM explicitly confirms.
 *
 * This split (preview vs. create) is the guardrail: there is simply no way to write
 * records from this action.
 */
public with sharing class AmaizePreviewGrantSchedule {

    /* ---------------- Action input ---------------- */
    public class Request {
        @InvocableVariable(
            label='Opportunity Name'
            description='The grant these schedule items belong to'
            required=true)
        public String opportunityName;

        @InvocableVariable(
            label='Schedule JSON'
            description='The proposed schedule as JSON: a totalAmount, a disbursements array (amount, dueDate, conditional, description), and a reports array (dueDate, type, description).'
            required=true)
        public String scheduleJson;
    }

    /* ---------------- Action output ---------------- */
    public class Result {
        @InvocableVariable(
            label='Preview Summary'
            description='Human-readable preview of the records that would be created')
        public String previewSummary;

        @InvocableVariable(
            label='Item Count'
            description='Total number of records that would be created')
        public Integer itemCount;
    }

    @InvocableMethod(
        label='Preview Grant Schedule'
        description='Shows the Gift Transactions and Grant Reports that WOULD be created from the proposed schedule. Does not create any records.')
    public static List<Result> preview(List<Request> requests) {
        List<Result> results = new List<Result>();
        for (Request req : requests) {
            Result r = new Result();
            try {
                // Reuse the shared parser so preview and create read the JSON identically.
                AmaizeScheduleParser.ParsedSchedule parsed = AmaizeScheduleParser.parse(req.scheduleJson);
                r.itemCount = parsed.disbursements.size() + parsed.reports.size();
                r.previewSummary = AmaizeScheduleParser.renderPreview(req.opportunityName, parsed);
            } catch (Exception e) {
                // If the JSON is malformed, explain rather than throwing an opaque error.
                r.itemCount = 0;
                r.previewSummary = 'I couldn\'t read the schedule details. Please restate the '
                    + 'disbursements (amount + due date) and reports (due date + type) and I\'ll preview them again.';
            }
            results.add(r);
        }
        return results;
    }
}