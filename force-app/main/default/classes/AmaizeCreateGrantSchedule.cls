/**
 * AmaizeCreateGrantSchedule — the write half of Step 3 (Generate Schedule).
 *
 * In plain terms: AFTER the RM has seen the preview and explicitly said yes, this
 * actually creates the Gift Transaction and Grant Report records for the grant.
 * The agent is instructed never to call this without a prior preview and an explicit
 * confirmation — and because this is a separate action from the preview, there is a
 * clean boundary the agent must cross deliberately.
 *
 * It resolves the grant by name (the LLM passes a name, Apex finds the record),
 * then inserts the records in one transaction. If the grant can't be uniquely
 * resolved, it creates nothing and explains why.
 */
public with sharing class AmaizeCreateGrantSchedule {

    /* ---------------- Action input ---------------- */
    public class Request {
        @InvocableVariable(
            label='Opportunity Name'
            description='The grant to attach the schedule to'
            required=true)
        public String opportunityName;

        @InvocableVariable(
            label='Schedule JSON'
            description='The confirmed schedule as JSON (same shape used in the preview).'
            required=true)
        public String scheduleJson;
    }

    /* ---------------- Action output ---------------- */
    public class Result {
        @InvocableVariable(
            label='Result Summary'
            description='Human-readable confirmation of what was created')
        public String resultSummary;

        @InvocableVariable(
            label='Created Count'
            description='How many records were created')
        public Integer createdCount;
    }

    @InvocableMethod(
        label='Create Grant Schedule'
        description='Creates the Gift Transaction and Grant Report records from a confirmed schedule. Only call after the user has seen the preview and explicitly confirmed.')
    public static List<Result> createSchedule(List<Request> requests) {
        List<Result> results = new List<Result>();

        // Resolve all referenced grant names to records in one query (no SOQL in a loop).
        Set<String> names = new Set<String>();
        for (Request req : requests) {
            if (String.isNotBlank(req.opportunityName)) names.add(req.opportunityName.trim());
        }
        // Restrict to A-maize-ing grants (Country_Tag__c != null) so the demo grants always
        // resolve even when the org holds 500+ unrelated opportunities.
        // AccountId is needed to populate DonorId on any Gift Commitment we create.
        List<Opportunity> opps = [
            SELECT Id, Name, AccountId FROM Opportunity
            WHERE StageName != 'Closed Lost' AND Country_Tag__c != null
            LIMIT 500
        ];

        // ----- Pass 1: resolve the grant and parse the schedule for every request -----
        // We hold one small work item per valid request so the writes can be done in bulk.
        List<WorkItem> work = new List<WorkItem>();
        for (Request req : requests) {
            Result r = new Result();
            r.createdCount = 0;

            // Find the single grant this schedule belongs to.
            Opportunity match = resolveOpp(req.opportunityName, opps);
            if (match == null) {
                r.resultSummary = 'I couldn\'t uniquely identify the grant "' + req.opportunityName
                    + '", so I did not create anything. Please confirm the exact opportunity name.';
                results.add(r);
                continue;
            }

            // Parse the schedule (no DML yet).
            AmaizeScheduleParser.ParsedSchedule parsed;
            try {
                parsed = AmaizeScheduleParser.parse(req.scheduleJson);
            } catch (Exception e) {
                r.resultSummary = 'I couldn\'t read the schedule details, so nothing was created. '
                    + 'Please restate the disbursements and reports.';
                results.add(r);
                continue;
            }

            if (parsed.disbursements.isEmpty() && parsed.reports.isEmpty()) {
                r.resultSummary = 'There were no schedule items to create for "' + match.Name + '".';
                results.add(r);
                continue;
            }

            WorkItem w = new WorkItem();
            w.match = match;
            w.parsed = parsed;
            w.result = r;
            work.add(w);
            results.add(r);
        }
        if (work.isEmpty()) {
            return results;
        }

        // ----- Resolve or create the Gift Commitment parent for grants that have reports -----
        // The customer's Grant Report is a master-detail child of Gift Commitment, so any report
        // row needs a parent commitment. Find an existing one for the grant; create it if absent.
        Set<Id> oppIdsNeedingCommitment = new Set<Id>();
        for (WorkItem w : work) {
            if (!w.parsed.reports.isEmpty()) oppIdsNeedingCommitment.add(w.match.Id);
        }
        Map<Id, Id> commitmentByOpp = new Map<Id, Id>();
        if (!oppIdsNeedingCommitment.isEmpty()) {
            for (GiftCommitment gc : [
                SELECT Id, OpportunityId FROM GiftCommitment
                WHERE OpportunityId IN :oppIdsNeedingCommitment
                ORDER BY CreatedDate ASC
            ]) {
                // First (oldest) commitment per grant wins, so the choice is deterministic.
                if (!commitmentByOpp.containsKey(gc.OpportunityId)) {
                    commitmentByOpp.put(gc.OpportunityId, gc.Id);
                }
            }
        }

        // ----- Write everything inside a savepoint: parents first, then schedule records.
        // If any insert fails, roll the whole thing back so nothing partial is left behind.
        Savepoint sp = Database.setSavepoint();
        try {
            // Create any Gift Commitments that don't already exist, in one insert.
            List<GiftCommitment> newCommitments = new List<GiftCommitment>();
            List<Id> oppsForNew = new List<Id>();
            for (Id oppId : oppIdsNeedingCommitment) {
                if (commitmentByOpp.containsKey(oppId)) continue;
                Opportunity o = oppById(oppId, opps);
                newCommitments.add(new GiftCommitment(
                    Name = '[AMAIZE_DEMO] ' + (o != null ? o.Name : 'Grant') + ' — Commitment',
                    OpportunityId = oppId,
                    DonorId = (o != null ? o.AccountId : null),
                    Status = 'Active'));
                oppsForNew.add(oppId);
            }
            if (!newCommitments.isEmpty()) {
                insert newCommitments;
                for (Integer i = 0; i < newCommitments.size(); i++) {
                    commitmentByOpp.put(oppsForNew[i], newCommitments[i].Id);
                }
            }

            // Build all the schedule records now that the parents exist, then insert once.
            List<SObject> allToInsert = new List<SObject>();
            for (WorkItem w : work) {
                Id gcId = commitmentByOpp.get(w.match.Id);
                List<SObject> recs = AmaizeScheduleParser.buildRecords(w.match.Id, gcId, w.parsed);
                w.result.createdCount = recs.size();
                w.result.resultSummary = '✅ Created ' + recs.size() + ' record'
                    + (recs.size() == 1 ? '' : 's') + ' for "' + w.match.Name + '" ('
                    + w.parsed.disbursements.size() + ' disbursement'
                    + (w.parsed.disbursements.size() == 1 ? '' : 's') + ', '
                    + w.parsed.reports.size() + ' report'
                    + (w.parsed.reports.size() == 1 ? '' : 's') + ').';
                allToInsert.addAll(recs);
            }
            if (!allToInsert.isEmpty()) {
                insert allToInsert;
            }
        } catch (Exception e) {
            // Undo the partial work and tell the RM nothing was saved.
            Database.rollback(sp);
            String msg = (e instanceof DmlException) ? ((DmlException) e).getDmlMessage(0) : e.getMessage();
            for (WorkItem w : work) {
                w.result.createdCount = 0;
                w.result.resultSummary = 'Something went wrong creating the records, so nothing was saved. '
                    + 'Error: ' + msg;
            }
        }
        return results;
    }

    /** A single request that resolved to a grant and parsed schedule, ready to write. */
    private class WorkItem {
        Opportunity match;
        AmaizeScheduleParser.ParsedSchedule parsed;
        Result result;
    }

    /** Find a previously queried Opportunity by Id (no extra SOQL). */
    private static Opportunity oppById(Id oppId, List<Opportunity> opps) {
        for (Opportunity o : opps) {
            if (o.Id == oppId) return o;
        }
        return null;
    }

    /** Resolve exactly one grant by name; return null if zero or more than one match. */
    private static Opportunity resolveOpp(String wantedName, List<Opportunity> opps) {
        // Use the shared token matcher so loose names (missing the en-dash, etc.) resolve.
        List<Opportunity> hits = AmaizeMatch.tokenMatch(wantedName, opps);
        return (hits.size() == 1) ? hits[0] : null;
    }
}