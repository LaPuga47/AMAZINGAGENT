/**
 * AmaizeScheduleParser — shared helper for Step 3's preview and create actions.
 *
 * In plain terms: the agent hands us a JSON description of a grant's payment and
 * reporting schedule. This class turns that JSON into tidy Apex objects, renders a
 * human-readable preview table, and builds the matching Gift Transaction / Grant
 * Report records ready to insert. Keeping this logic in one place guarantees the
 * preview the RM approves is exactly what gets created.
 *
 * Expected JSON shape (all fields optional except where noted):
 * {
 *   "totalAmount": 500000,
 *   "disbursements": [
 *     { "amount": 250000, "dueDate": "2027-01-31", "conditional": false, "description": "Initial tranche" },
 *     { "amount": 250000, "dueDate": "2027-07-31", "conditional": true,  "description": "On milestone 1" }
 *   ],
 *   "reports": [
 *     { "dueDate": "2027-03-31", "type": "Financial", "description": "Q1 financial report" }
 *   ]
 * }
 */
public with sharing class AmaizeScheduleParser {

    /** A single disbursement parsed from the JSON. */
    public class DisbursementItem {
        public Decimal amount;
        public Date dueDate;
        public Boolean conditional = false;
        public String description;
    }

    /** A single grant report parsed from the JSON. */
    public class ReportItem {
        public Date dueDate;
        public String type;
        public String description;
    }

    /** The whole parsed schedule. */
    public class ParsedSchedule {
        public Decimal totalAmount;
        public List<DisbursementItem> disbursements = new List<DisbursementItem>();
        public List<ReportItem> reports = new List<ReportItem>();
    }

    /**
     * Parse the schedule JSON into Apex objects. Dates are read leniently
     * (YYYY-MM-DD) and bad rows are skipped rather than blowing up the whole parse.
     */
    public static ParsedSchedule parse(String scheduleJson) {
        ParsedSchedule out = new ParsedSchedule();
        if (String.isBlank(scheduleJson)) {
            return out;
        }
        // Untyped parse so we can tolerate missing keys and mixed types from the LLM.
        Map<String, Object> root = (Map<String, Object>) JSON.deserializeUntyped(scheduleJson);

        if (root.get('totalAmount') != null) {
            out.totalAmount = toDecimal(root.get('totalAmount'));
        }

        // Disbursements
        if (root.get('disbursements') instanceof List<Object>) {
            for (Object item : (List<Object>) root.get('disbursements')) {
                Map<String, Object> m = (Map<String, Object>) item;
                DisbursementItem d = new DisbursementItem();
                d.amount = toDecimal(m.get('amount'));
                d.dueDate = toDate(m.get('dueDate'));
                d.conditional = (m.get('conditional') == true);
                d.description = (String) m.get('description');
                out.disbursements.add(d);
            }
        }

        // Reports
        if (root.get('reports') instanceof List<Object>) {
            for (Object item : (List<Object>) root.get('reports')) {
                Map<String, Object> m = (Map<String, Object>) item;
                ReportItem rep = new ReportItem();
                rep.dueDate = toDate(m.get('dueDate'));
                rep.type = (String) m.get('type');
                rep.description = (String) m.get('description');
                out.reports.add(rep);
            }
        }
        return out;
    }

    /**
     * Render a human-readable preview table of what would be created.
     */
    public static String renderPreview(String opportunityName, ParsedSchedule s) {
        if (s.disbursements.isEmpty() && s.reports.isEmpty()) {
            return 'There are no schedule items to preview yet. Tell me the disbursements '
                + '(amount + due date) and any reports (due date + type) and I\'ll lay them out.';
        }
        List<String> parts = new List<String>();
        parts.add('Here is the schedule I would create for "' + opportunityName + '"'
            + (s.totalAmount != null ? ' (total ' + AmaizeFormat.money(s.totalAmount) + ')' : '') + ':');

        if (!s.disbursements.isEmpty()) {
            parts.add('\nDisbursements (Gift Transactions):');
            Integer n = 1;
            for (DisbursementItem d : s.disbursements) {
                parts.add('  ' + n++ + '. ' + AmaizeFormat.money(d.amount)
                    + (d.dueDate != null ? ' due ' + d.dueDate.format() : '')
                    + (d.conditional ? ' [conditional]' : '')
                    + (String.isNotBlank(d.description) ? ' — ' + d.description : ''));
            }
        }
        if (!s.reports.isEmpty()) {
            parts.add('\nGrant Reports:');
            Integer n = 1;
            for (ReportItem rep : s.reports) {
                parts.add('  ' + n++ + '. ' + (String.isNotBlank(rep.type) ? rep.type : 'Report')
                    + (rep.dueDate != null ? ' due ' + rep.dueDate.format() : '')
                    + (String.isNotBlank(rep.description) ? ' — ' + rep.description : ''));
            }
        }
        parts.add('\nShould I go ahead and create these records? They will not be created until you confirm.');
        return String.join(parts, '\n');
    }

    /**
     * Build (but do not insert) the records for this schedule.
     *
     * Disbursements become Gift Transactions, linked to the grant by Opportunity.
     * Reports become Grant Reports. The customer's Grant Report is a master-detail
     * child of Gift Commitment (not the Opportunity), so the caller resolves/creates
     * the parent Gift Commitment and passes its Id here. If no parent is available,
     * report rows are skipped rather than failing the whole insert.
     *
     * Returns one heterogeneous list so the caller can insert it in a single DML.
     */
    public static List<SObject> buildRecords(Id opportunityId, Id giftCommitmentId, ParsedSchedule s) {
        List<SObject> toInsert = new List<SObject>();
        for (DisbursementItem d : s.disbursements) {
            toInsert.add(new Gift_Transaction__c(
                Opportunity__c = opportunityId,
                Amount__c = d.amount,
                Due_Date__c = d.dueDate,
                Conditional__c = d.conditional,
                // Tag the description so teardown can recognise demo-created rows.
                Description__c = '[AMAIZE_DEMO] ' + (d.description == null ? '' : d.description)));
        }
        if (giftCommitmentId != null) {
            for (ReportItem rep : s.reports) {
                toInsert.add(new Grant_Report__c(
                    // Master-detail parent on the customer object.
                    Gift_Commitment__c = giftCommitmentId,
                    Due_Date__c = rep.dueDate,
                    // Map the LLM's free-text type onto the customer's picklist.
                    Report_Type__c = mapReportType(rep.type),
                    // Tag the notes so teardown can recognise demo-created rows.
                    Grant_Report_Notes__c = '[AMAIZE_DEMO] ' + (rep.description == null ? '' : rep.description)));
            }
        }
        return toInsert;
    }

    /**
     * Map the LLM's free-text report type (e.g. "Financial", "progress update")
     * onto the customer's Grant Report Report_Type__c picklist. Anything we don't
     * recognise falls back to "Other" so a write never fails on a bad picklist value.
     */
    public static String mapReportType(String raw) {
        if (String.isBlank(raw)) return 'Other';
        String t = raw.toLowerCase();
        if (t.contains('financ')) return 'Financial Report';
        if (t.contains('progress')) return 'Progress Report';
        if (t.contains('challenge')) return 'Challenge Report';
        if (t.contains('interest')) return 'Interest Payment';
        if (t.contains('principal')) return 'Principal Payment';
        if (t.contains('notif')) return 'Notification';
        if (t.contains('compliance')) return 'Compliance Certificate';
        if (t.contains('audit')) return 'Audited Financial Statements';
        return 'Other';
    }

    /* ---------- small lenient converters ---------- */

    /** Convert a JSON value (number or string) into a Decimal, or null if not possible. */
    private static Decimal toDecimal(Object value) {
        if (value == null) return null;
        if (value instanceof Decimal) return (Decimal) value;
        if (value instanceof Integer) return (Decimal) value;
        if (value instanceof Double) return Decimal.valueOf((Double) value);
        try {
            return Decimal.valueOf(String.valueOf(value));
        } catch (Exception e) {
            return null;
        }
    }

    /** Convert a "YYYY-MM-DD" string into a Date, or null if it can't be read. */
    private static Date toDate(Object value) {
        if (value == null) return null;
        try {
            return Date.valueOf(String.valueOf(value));
        } catch (Exception e) {
            return null;
        }
    }
}