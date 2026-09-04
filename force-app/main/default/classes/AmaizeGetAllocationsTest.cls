/**
 * AmaizeGetAllocationsTest — Funding Allocation drill-down for a governed Headroom scope:
 * groups allocations by Opportunity, splits Secured vs Likely/Pipeline, reconciles per-opp
 * totals to the shown allocations, filters by type, pages beyond 15, and emits clickable
 * record links. Reuses the same governed retrieval as competing-grants analysis. Read-only.
 */
@isTest
private class AmaizeGetAllocationsTest {

    @TestSetup
    static void setup() {
        Budget_Scenario__c s = HeadroomTestData.makeCurrentScenario();
        // Two Core Program - KE lines: the governed Kenya Core Program FY2027 population.
        HeadroomTestData.makeLine(s.Id, 'Kenya', 'Core Program - KE', 'N/A', 'Extension', 'N/A', 'N/A',
            -1000000, 300000, 0, 0);
        HeadroomTestData.makeLine(s.Id, 'Kenya', 'Core Program - KE', 'N/A', 'Field Operations', 'N/A', 'N/A',
            -500000, 100000, 0, 0);
    }

    private static List<Id> coreLineIds() {
        List<Id> ids = new List<Id>();
        for (Budget_Line__c bl : [SELECT Id FROM Budget_Line__c WHERE BusinessUnit__c = 'Core Program - KE']) {
            ids.add(bl.Id);
        }
        return ids;
    }

    private static AmaizeGetAllocations.Request req(String program, String country, Integer fy) {
        AmaizeGetAllocations.Request r = new AmaizeGetAllocations.Request();
        r.program = program; r.country = country; r.fiscalYear = fy;
        return r;
    }
    private static AmaizeGetAllocations.Result run(AmaizeGetAllocations.Request r) {
        return AmaizeGetAllocations.get(new List<AmaizeGetAllocations.Request>{ r })[0];
    }

    @isTest
    static void groupsSecuredAndPipelineByOpportunityWithLinks() {
        List<Id> lines = coreLineIds();
        HeadroomTestData.makeOppAllocations('Secured', lines, 12000, 'Kenya', 'Core Program - KE');   // 1 opp, 2 x 12K
        HeadroomTestData.makeOppAllocations('Pipeline', lines, 20000, 'Kenya', 'Core Program - KE');  // 1 opp, 2 x 20K

        Test.startTest();
        AmaizeGetAllocations.Result res = run(req('Core Program', 'Kenya', 2027));
        Test.stopTest();

        System.assertEquals(true, res.found);
        System.assertEquals(4, res.matchCount, res.summary);
        System.assert(res.summary.contains('4 Funding Allocation records across 2 Opportunities'), res.summary);
        // Both sections present and separated.
        System.assert(res.summary.contains('**SECURED**'), res.summary);
        System.assert(res.summary.contains('**LIKELY / PIPELINE**'), res.summary);
        // No implementation terminology.
        // (check the FY2027 form, not the bare 'FY' substring — Salesforce record IDs in URLs can contain "FY").
        System.assert(!res.summary.contains('mapped') && !res.summary.contains('exposure') && !res.summary.contains('FY2027'),
            'no mapped/exposure/FY2027: ' + res.summary);
        // Opportunity group heading is a clickable link (kept a bare link so the model preserves it).
        System.assert(res.summary.contains('/lightning/r/Opportunity/'),
            'clickable Opportunity group heading: ' + res.summary);
        // Lean default line: clickable Allocation, Opportunity, and Restriction in the summary.
        System.assert(res.summary.contains('/lightning/r/Allocation__c/'), res.summary);
        System.assert(res.summary.contains('/lightning/r/Opportunity/'), res.summary);
        System.assert(res.summary.contains('/lightning/r/Restriction__c/'), res.summary);
        System.assert(res.summary.contains('| Restriction: ['), 'restriction inline + clickable: ' + res.summary);
        // Allocation Type is conveyed by the section heading, not repeated on each row.
        System.assert(!res.summary.contains('| Secured |') && !res.summary.contains('| Pipeline |')
            && !res.summary.contains('| Likely |'), 'type not repeated on rows: ' + res.summary);
        // No empty placeholder when a field (status) is blank.
        System.assert(!res.summary.contains('| — |') && !res.summary.contains('| —\n'), 'no empty placeholder: ' + res.summary);
        // Allocation Type still available internally for grouping/filtering.
        System.assert(res.resultsJson.contains('allocationType'), res.resultsJson);
        // Gift Commitment and Budget Line stay available in the machine-readable JSON (drill-down).
        System.assert(res.resultsJson.contains('budgetLineUrl') && res.resultsJson.contains('giftCommitmentUrl'), res.resultsJson);
    }

    @isTest
    static void filtersByAllocationType() {
        List<Id> lines = coreLineIds();
        HeadroomTestData.makeOppAllocations('Secured', lines, 12000, 'Kenya', 'Core Program - KE');
        HeadroomTestData.makeOppAllocations('Pipeline', lines, 20000, 'Kenya', 'Core Program - KE');

        Test.startTest();
        AmaizeGetAllocations.Request r = req('Core Program', 'Kenya', 2027);
        r.allocationType = 'Pipeline';
        AmaizeGetAllocations.Result res = run(r);
        Test.stopTest();

        System.assertEquals(2, res.matchCount, res.summary);
        System.assert(!res.summary.contains('**SECURED**'), 'type filter excludes secured: ' + res.summary);
        System.assert(res.summary.contains('**LIKELY / PIPELINE**'), res.summary);
    }

    @isTest
    static void mediumSetRendersAllInlineNoPartialMessage() {
        Id line = coreLineIds()[0];
        List<HeadroomTestData.AllocSpec> specs = new List<HeadroomTestData.AllocSpec>();
        for (Integer i = 0; i < 16; i++) { specs.add(new HeadroomTestData.AllocSpec('Pipeline', 5000)); }
        HeadroomTestData.makeAllocations(specs, line, 'Kenya', 'Core Program - KE');   // 16 opps x 1 alloc

        Test.startTest();
        AmaizeGetAllocations.Result res = run(req('Core Program', 'Kenya', 2027));
        Test.stopTest();

        System.assertEquals(16, res.matchCount, 'all 16 counted');
        // A medium set (<= 20) renders in FULL — every record clickable, no paging message.
        System.assertEquals(16, res.summary.countMatches('/lightning/r/Allocation__c/'), 'all 16 clickable: ' + res.summary);
        System.assert(!res.summary.containsIgnoreCase('Showing '), 'no "Showing X of Y" message: ' + res.summary);
        System.assert(!res.summary.containsIgnoreCase('Ask to see all'), 'no "Ask to see all" message: ' + res.summary);
        System.assert(!res.summary.containsIgnoreCase('next page'), res.summary);
        System.assert(res.summary.contains('Would you like these summarized by Opportunity or Restriction?'), res.summary);
    }

    @isTest
    static void largeSetSummarizesUnlessShowAll() {
        Id line = coreLineIds()[0];
        List<HeadroomTestData.AllocSpec> specs = new List<HeadroomTestData.AllocSpec>();
        for (Integer i = 0; i < 22; i++) { specs.add(new HeadroomTestData.AllocSpec('Pipeline', 5000)); }
        HeadroomTestData.makeAllocations(specs, line, 'Kenya', 'Core Program - KE');   // 22 opps x 1 alloc

        Test.startTest();
        AmaizeGetAllocations.Result res = run(req('Core Program', 'Kenya', 2027));
        AmaizeGetAllocations.Request r = req('Core Program', 'Kenya', 2027); r.showAll = true;
        AmaizeGetAllocations.Result full = run(r);
        Test.stopTest();

        // Above 20 and no explicit "show all": concise count summary + offer, no rows dumped.
        System.assertEquals(22, res.matchCount);
        System.assertEquals(0, res.summary.countMatches('/lightning/r/Allocation__c/'), 'no rows listed for >20: ' + res.summary);
        System.assert(res.summary.contains('22 Funding Allocation records'), res.summary);
        System.assert(res.summary.contains('Would you like the full Allocation list, or a summary by Opportunity or Restriction?'), res.summary);
        System.assert(!res.summary.containsIgnoreCase('Showing '), res.summary);
        // Explicit show all: every record rendered, no truncation note (well under the 200 cap).
        System.assertEquals(22, full.summary.countMatches('/lightning/r/Allocation__c/'), 'showAll returns all 22');
        System.assert(!full.summary.contains('exceeds the response'), full.summary);
    }

    @isTest
    static void sixRecordsAllRenderTogether() {
        // Bulk factory (single batched DML) avoids the per-chain DLRS-rollup SOQL blowup.
        Id line = coreLineIds()[0];
        List<HeadroomTestData.AllocSpec> specs = new List<HeadroomTestData.AllocSpec>();
        for (Integer i = 0; i < 6; i++) { specs.add(new HeadroomTestData.AllocSpec('Pipeline', 5000)); }
        HeadroomTestData.makeAllocations(specs, line, 'Kenya', 'Core Program - KE');   // 6 opps x 1 alloc

        Test.startTest();
        AmaizeGetAllocations.Result res = run(req('Core Program', 'Kenya', 2027));
        Test.stopTest();

        System.assertEquals(6, res.matchCount, res.summary);
        System.assert(res.summary.contains('6 Funding Allocation records across 6 Opportunities'), res.summary);
        // All 6 render in one response with clickable links — no "Showing 5 of 6" paging.
        System.assertEquals(6, res.summary.countMatches('/lightning/r/Allocation__c/'), 'all 6 clickable: ' + res.summary);
        System.assert(res.summary.contains('**LIKELY / PIPELINE**'), res.summary);
        System.assert(!res.summary.containsIgnoreCase('Showing ') && !res.summary.containsIgnoreCase('Ask to see all'),
            'no partial-result message for 6 records: ' + res.summary);
    }

    @isTest
    static void noAllocationsIsReportedNotFabricated() {
        // Lines exist (from setup) but no allocations were created.
        AmaizeGetAllocations.Result res = run(req('Core Program', 'Kenya', 2027));
        System.assertEquals(true, res.found);
        System.assertEquals(0, res.matchCount);
        System.assert(res.summary.contains('no Funding Allocation records match'), res.summary);
    }

    @isTest
    static void noQualifyingLines() {
        AmaizeGetAllocations.Result res = run(req('Trees', 'Kenya', 2027));   // no Trees lines seeded
        System.assertEquals(false, res.found);
        System.assert(res.summary.contains('No qualifying Budget Line records'), res.summary);
    }

    @isTest
    static void performsNoDml() {
        List<Id> lines = coreLineIds();
        HeadroomTestData.makeOppAllocations('Secured', lines, 12000, 'Kenya', 'Core Program - KE');
        Test.startTest();
        run(req('Core Program', 'Kenya', 2027));
        System.assertEquals(0, Limits.getDmlStatements(), 'Allocation drill-down must never write data');
        Test.stopTest();
    }
}
