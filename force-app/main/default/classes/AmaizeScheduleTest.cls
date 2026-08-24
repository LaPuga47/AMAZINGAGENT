/**
 * Tests for Step 3: AmaizePreviewGrantSchedule, AmaizeCreateGrantSchedule,
 * AmaizeScheduleParser, and AmaizeFormat.
 * Covers: preview (no writes), create happy path, malformed JSON, ambiguous grant,
 * empty schedule, and the currency formatting helper.
 */
@isTest
private class AmaizeScheduleTest {

    @TestSetup
    static void setup() {
        AmaizeTestData.makeAll();
    }

    // A valid schedule payload with 2 disbursements and 1 report.
    private static String validJson() {
        return '{'
            + '"totalAmount":500000,'
            + '"disbursements":['
            + '{"amount":250000,"dueDate":"2027-01-31","conditional":false,"description":"Initial tranche"},'
            + '{"amount":250000,"dueDate":"2027-07-31","conditional":true,"description":"On milestone 1"}'
            + '],'
            + '"reports":[{"dueDate":"2027-03-31","type":"Financial","description":"Q1 report"}]'
            + '}';
    }

    @isTest
    static void previewDoesNotCreateRecords() {
        // Preview must show the items but write nothing to the database.
        AmaizePreviewGrantSchedule.Request req = new AmaizePreviewGrantSchedule.Request();
        req.opportunityName = 'Continental Dev Bank Kenya Carbon';
        req.scheduleJson = validJson();

        Test.startTest();
        AmaizePreviewGrantSchedule.Result r =
            AmaizePreviewGrantSchedule.preview(new List<AmaizePreviewGrantSchedule.Request>{ req })[0];
        Test.stopTest();

        System.assertEquals(3, r.itemCount, 'Preview should count 2 disbursements + 1 report');
        System.assert(r.previewSummary.contains('would create'), 'Should describe a preview, not a creation');
        System.assert(r.previewSummary.contains('confirm'), 'Should ask for confirmation');
        // Prove nothing was written.
        System.assertEquals(0, [SELECT COUNT() FROM Gift_Transaction__c], 'Preview must not create Gift Transactions');
        System.assertEquals(0, [SELECT COUNT() FROM Grant_Report__c], 'Preview must not create Grant Reports');
    }

    @isTest
    static void createInsertsRecordsLinkedToGrant() {
        // After confirmation, create should insert the records and link them to the grant.
        AmaizeCreateGrantSchedule.Request req = new AmaizeCreateGrantSchedule.Request();
        req.opportunityName = 'Continental Dev Bank Kenya Carbon';
        req.scheduleJson = validJson();

        Test.startTest();
        AmaizeCreateGrantSchedule.Result r =
            AmaizeCreateGrantSchedule.createSchedule(new List<AmaizeCreateGrantSchedule.Request>{ req })[0];
        Test.stopTest();

        System.assertEquals(3, r.createdCount, 'Should create 2 disbursements + 1 report');
        System.assertEquals(2, [SELECT COUNT() FROM Gift_Transaction__c], 'Two Gift Transactions created');
        System.assertEquals(1, [SELECT COUNT() FROM Grant_Report__c], 'One Grant Report created');
        // Confirm the link back to the grant.
        Id carbonId = AmaizeTestData.oppId('Continental Dev Bank');
        System.assertEquals(2,
            [SELECT COUNT() FROM Gift_Transaction__c WHERE Opportunity__c = :carbonId],
            'Gift Transactions should be linked to the Carbon grant');
        // The Grant Report is a master-detail child of Gift Commitment; the action must have
        // created a parent commitment for this grant and parented the report to it.
        GiftCommitment gc = [
            SELECT Id, OpportunityId FROM GiftCommitment WHERE OpportunityId = :carbonId LIMIT 1];
        System.assertEquals(carbonId, gc.OpportunityId, 'Commitment should link to the Carbon grant');
        Grant_Report__c gr = [
            SELECT Gift_Commitment__c, Report_Type__c FROM Grant_Report__c LIMIT 1];
        System.assertEquals(gc.Id, gr.Gift_Commitment__c, 'Report should be parented to the commitment');
        System.assertEquals('Financial Report', gr.Report_Type__c, '"Financial" maps to the picklist value');
    }

    @isTest
    static void createReusesExistingCommitment() {
        // If a Gift Commitment already exists for the grant, the action reuses it rather
        // than creating a second one. The shared test factory seeds one commitment per demo
        // grant, so that pre-existing commitment IS the "existing" one under test here; we
        // assert the count is UNCHANGED by create (the true "reuse, not duplicate" invariant)
        // rather than hard-coding a number that depends on factory internals.
        Id carbonId = AmaizeTestData.oppId('Continental Dev Bank');
        Integer before =
            [SELECT COUNT() FROM GiftCommitment WHERE OpportunityId = :carbonId];
        System.assert(before >= 1, 'The factory should have seeded a commitment for the Carbon grant');

        AmaizeCreateGrantSchedule.Request req = new AmaizeCreateGrantSchedule.Request();
        req.opportunityName = 'Continental Dev Bank Kenya Carbon';
        req.scheduleJson = validJson();

        Test.startTest();
        AmaizeCreateGrantSchedule.createSchedule(new List<AmaizeCreateGrantSchedule.Request>{ req });
        Test.stopTest();

        System.assertEquals(before,
            [SELECT COUNT() FROM GiftCommitment WHERE OpportunityId = :carbonId],
            'Existing commitment should be reused, not duplicated');
        System.assertEquals(1, [SELECT COUNT() FROM Grant_Report__c], 'One Grant Report created under it');
    }

    @isTest
    static void reportTypeMappingCoversCommonInputs() {
        // The LLM passes free text; we map it onto the customer's Report_Type__c picklist.
        System.assertEquals('Financial Report', AmaizeScheduleParser.mapReportType('financial'), 'financial');
        System.assertEquals('Progress Report', AmaizeScheduleParser.mapReportType('Progress update'), 'progress');
        System.assertEquals('Challenge Report', AmaizeScheduleParser.mapReportType('challenge'), 'challenge');
        System.assertEquals('Other', AmaizeScheduleParser.mapReportType('something unknown'), 'fallback');
        System.assertEquals('Other', AmaizeScheduleParser.mapReportType(null), 'null fallback');
    }

    @isTest
    static void createWithUnknownGrantCreatesNothing() {
        // If the grant name can't be resolved, nothing is created.
        AmaizeCreateGrantSchedule.Request req = new AmaizeCreateGrantSchedule.Request();
        req.opportunityName = 'No Such Grant Anywhere';
        req.scheduleJson = validJson();

        Test.startTest();
        AmaizeCreateGrantSchedule.Result r =
            AmaizeCreateGrantSchedule.createSchedule(new List<AmaizeCreateGrantSchedule.Request>{ req })[0];
        Test.stopTest();

        System.assertEquals(0, r.createdCount, 'Nothing should be created for an unknown grant');
        System.assert(r.resultSummary.contains('couldn\'t uniquely identify'), 'Should explain the miss');
        System.assertEquals(0, [SELECT COUNT() FROM Gift_Transaction__c], 'No records created');
    }

    @isTest
    static void createWithAmbiguousGrantCreatesNothing() {
        // "Kenya Core Program" matches 2 grants -> ambiguous -> create nothing.
        AmaizeCreateGrantSchedule.Request req = new AmaizeCreateGrantSchedule.Request();
        req.opportunityName = 'Kenya Core Program';
        req.scheduleJson = validJson();

        Test.startTest();
        AmaizeCreateGrantSchedule.Result r =
            AmaizeCreateGrantSchedule.createSchedule(new List<AmaizeCreateGrantSchedule.Request>{ req })[0];
        Test.stopTest();

        System.assertEquals(0, r.createdCount, 'Ambiguous grant should create nothing');
        System.assertEquals(0, [SELECT COUNT() FROM Gift_Transaction__c], 'No records created');
    }

    @isTest
    static void malformedJsonIsHandledGracefully() {
        // Bad JSON should produce a friendly message, not an unhandled exception.
        AmaizePreviewGrantSchedule.Request req = new AmaizePreviewGrantSchedule.Request();
        req.opportunityName = 'Continental Dev Bank Kenya Carbon';
        req.scheduleJson = 'this is not json {{{';

        Test.startTest();
        AmaizePreviewGrantSchedule.Result r =
            AmaizePreviewGrantSchedule.preview(new List<AmaizePreviewGrantSchedule.Request>{ req })[0];
        Test.stopTest();

        System.assertEquals(0, r.itemCount, 'Malformed JSON yields zero items');
        System.assert(r.previewSummary.contains('couldn\'t read'), 'Should explain it could not read the schedule');
    }

    @isTest
    static void emptyScheduleSaysNothingToPreview() {
        // An empty schedule should prompt for details rather than show an empty table.
        AmaizePreviewGrantSchedule.Request req = new AmaizePreviewGrantSchedule.Request();
        req.opportunityName = 'Continental Dev Bank Kenya Carbon';
        req.scheduleJson = '{"disbursements":[],"reports":[]}';

        Test.startTest();
        AmaizePreviewGrantSchedule.Result r =
            AmaizePreviewGrantSchedule.preview(new List<AmaizePreviewGrantSchedule.Request>{ req })[0];
        Test.stopTest();

        System.assertEquals(0, r.itemCount, 'No items to preview');
        System.assert(r.previewSummary.contains('no schedule items'), 'Should ask for the details');
    }

    @isTest
    static void createWithEmptyScheduleCreatesNothing() {
        // A resolvable grant but an empty schedule -> nothing to create, friendly message.
        AmaizeCreateGrantSchedule.Request req = new AmaizeCreateGrantSchedule.Request();
        req.opportunityName = 'Continental Dev Bank Kenya Carbon';
        req.scheduleJson = '{"disbursements":[],"reports":[]}';

        Test.startTest();
        AmaizeCreateGrantSchedule.Result r =
            AmaizeCreateGrantSchedule.createSchedule(new List<AmaizeCreateGrantSchedule.Request>{ req })[0];
        Test.stopTest();

        System.assertEquals(0, r.createdCount, 'Empty schedule creates nothing');
        System.assert(r.resultSummary.contains('no schedule items'), 'Should say there were none');
        System.assertEquals(0, [SELECT COUNT() FROM Gift_Transaction__c], 'No records created');
    }

    @isTest
    static void createWithMalformedJsonCreatesNothing() {
        // Resolvable grant but unreadable JSON -> create nothing, explain.
        AmaizeCreateGrantSchedule.Request req = new AmaizeCreateGrantSchedule.Request();
        req.opportunityName = 'Continental Dev Bank Kenya Carbon';
        req.scheduleJson = 'not valid json {{{';

        Test.startTest();
        AmaizeCreateGrantSchedule.Result r =
            AmaizeCreateGrantSchedule.createSchedule(new List<AmaizeCreateGrantSchedule.Request>{ req })[0];
        Test.stopTest();

        System.assertEquals(0, r.createdCount, 'Malformed JSON creates nothing');
        System.assert(r.resultSummary.contains('couldn\'t read'), 'Should explain it could not read the schedule');
    }

    @isTest
    static void parserHandlesBlankAndBadValues() {
        // Blank JSON -> empty schedule.
        AmaizeScheduleParser.ParsedSchedule blank = AmaizeScheduleParser.parse('');
        System.assertEquals(0, blank.disbursements.size(), 'Blank JSON yields no disbursements');
        System.assertEquals(0, blank.reports.size(), 'Blank JSON yields no reports');

        // Bad date and non-numeric amount should be tolerated (parsed as null), not throw.
        String messy = '{"disbursements":[{"amount":"not-a-number","dueDate":"not-a-date"}],'
            + '"reports":[{"dueDate":"also-bad","type":"Final"}]}';
        AmaizeScheduleParser.ParsedSchedule p = AmaizeScheduleParser.parse(messy);
        System.assertEquals(1, p.disbursements.size(), 'Disbursement row still parsed');
        System.assertEquals(null, p.disbursements[0].amount, 'Bad amount becomes null');
        System.assertEquals(null, p.disbursements[0].dueDate, 'Bad date becomes null');
        System.assertEquals(1, p.reports.size(), 'Report row still parsed');

        // renderPreview on an empty schedule prompts for details.
        AmaizeScheduleParser.ParsedSchedule empty = new AmaizeScheduleParser.ParsedSchedule();
        System.assert(AmaizeScheduleParser.renderPreview('X', empty).contains('no schedule items'),
            'Empty preview asks for details');
    }

    @isTest
    static void parserReadsNumericAndDecimalAmounts() {
        // Integer, decimal, and string amounts all convert correctly.
        String json = '{"disbursements":['
            + '{"amount":100,"dueDate":"2027-01-01"},'
            + '{"amount":250000.50,"dueDate":"2027-02-01"},'
            + '{"amount":"500000","dueDate":"2027-03-01"}]}';
        AmaizeScheduleParser.ParsedSchedule p = AmaizeScheduleParser.parse(json);
        System.assertEquals(100, p.disbursements[0].amount, 'Integer amount');
        System.assertEquals(250000.50, p.disbursements[1].amount, 'Decimal amount');
        System.assertEquals(500000, p.disbursements[2].amount, 'String amount converted');
    }

    @isTest
    static void formatHelperRendersFriendlyAmounts() {
        // Verify the human-friendly currency strings used throughout the agent.
        System.assertEquals('$1.1M', AmaizeFormat.money(1100000), 'Millions with one decimal');
        System.assertEquals('$2M', AmaizeFormat.money(2000000), 'Whole millions drop the decimal');
        System.assertEquals('$350K', AmaizeFormat.money(350000), 'Thousands');
        System.assertEquals('-$150K', AmaizeFormat.money(-150000), 'Negatives keep the minus in front');
        System.assertEquals('$0', AmaizeFormat.money(0), 'Zero');
        System.assertEquals('$0', AmaizeFormat.money(null), 'Null treated as zero');
    }
}