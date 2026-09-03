/**
 * HeadroomNextYearTest — next-available-year guidance for no-Headroom responses.
 *
 * When a Program-Mode year has no available Headroom (fully funded or overfunded), the agent
 * looks forward through the years that actually have Budget Line data for the SAME country +
 * program and leads the user to the earliest future year with available Headroom — reusing the
 * existing aggregate() per year, never inventing a year. Read-only.
 */
@isTest
private class HeadroomNextYearTest {

    @TestSetup
    static void setup() {
        HeadroomTestData.makeCurrentScenario();   // current scenario anchors "current" lines
    }

    private static Id scenarioId() {
        return [SELECT Id FROM Budget_Scenario__c WHERE Is_Current_Scenario__c = true LIMIT 1].Id;
    }

    // Kenya Trees line for a given year with the given budget/secured (likely/pipeline 0).
    private static void treesLine(String year, Decimal budget, Decimal secured) {
        HeadroomTestData.makeLineForYear(scenarioId(), year, 'Kenya', 'Farm Input Sales - KE',
            'N/A', 'Trees', 'N/A', 'N/A', budget, secured, 0, 0);
    }

    private static AmaizeAnalyzeHeadroom.Request req(String program, String country, Integer fy) {
        AmaizeAnalyzeHeadroom.Request r = new AmaizeAnalyzeHeadroom.Request();
        r.program = program; r.country = country; r.fiscalYear = fy;
        return r;
    }
    private static AmaizeAnalyzeHeadroom.Result run(AmaizeAnalyzeHeadroom.Request r) {
        return AmaizeAnalyzeHeadroom.analyze(new List<AmaizeAnalyzeHeadroom.Request>{ r })[0];
    }

    // Test 1 — 2027 overfunded, 2028 available => lead to 2028.
    @isTest
    static void overfundedThisYearAvailableNextYear() {
        treesLine('2027', -500000, 1000000);   // forecast HR -500K (overfunded)
        treesLine('2028', -800000, 100000);    // forecast HR +700K (available)

        Test.startTest();
        AmaizeAnalyzeHeadroom.Result res = run(req('Trees', 'Kenya', 2027));
        Test.stopTest();

        System.assert(res.summary.contains('no available Headroom in 2027'), res.summary);
        System.assert(res.summary.contains('overfunded by'), res.summary);
        System.assert(res.summary.contains('next year with available Headroom is 2028'), res.summary);
        System.assert(res.summary.contains(AmaizeFormat.money(700000, null)), 'shows 2028 headroom: ' + res.summary);
        System.assert(res.summary.contains('review the 2028 funding position'), res.summary);
    }

    // Test 2 — 2027 fully funded, 2028 fully funded, 2029 available => earliest is 2029 (not skipped earlier).
    @isTest
    static void skipsFullyFundedYearsToFirstAvailable() {
        treesLine('2027', -500000, 500000);    // HR 0 (fully funded)
        treesLine('2028', -500000, 500000);    // HR 0 (fully funded)
        treesLine('2029', -1200000, 0);        // HR +1.2M (available)

        Test.startTest();
        AmaizeAnalyzeHeadroom.Result res = run(req('Trees', 'Kenya', 2027));
        Test.stopTest();

        System.assert(res.summary.contains('fully funded in 2027'), res.summary);
        System.assert(res.summary.contains('next year with available Headroom is 2029'), res.summary);
        System.assert(!res.summary.contains('2028'), 'must not jump to or stop at 2028: ' + res.summary);
    }

    // Test 3 — no future year has room => say so across the searched span + alternative follow-up.
    @isTest
    static void noFutureHeadroomFallsBackToAlternatives() {
        treesLine('2027', -500000, 1000000);   // overfunded
        treesLine('2028', -500000, 1000000);   // overfunded

        Test.startTest();
        AmaizeAnalyzeHeadroom.Result res = run(req('Trees', 'Kenya', 2027));
        Test.stopTest();

        System.assert(res.summary.contains('no available Headroom from 2027 through 2028'), res.summary);
        System.assert(res.summary.contains('Trees in other countries')
            && res.summary.contains('other programs in Kenya'), 'alternative follow-up: ' + res.summary);
        System.assert(!res.summary.containsIgnoreCase('next year with available'), res.summary);
    }

    // Test 4 — the requested year already has available Headroom => normal positive answer, no lookahead.
    @isTest
    static void availableThisYearDoesNotLookAhead() {
        treesLine('2027', -800000, 100000);    // available +700K
        treesLine('2028', -800000, 100000);    // available (should be ignored)

        Test.startTest();
        AmaizeAnalyzeHeadroom.Result res = run(req('Trees', 'Kenya', 2027));
        Test.stopTest();

        System.assert(res.summary.contains('room for additional fundraising'), res.summary);
        System.assert(!res.summary.contains('next year with available Headroom'), res.summary);
        System.assert(!res.summary.contains('2028'), 'no lookahead when this year has room: ' + res.summary);
    }

    // Test 5 — no Budget Line records for the requested year => cannot determine, NOT no-headroom lookahead.
    @isTest
    static void noDataIsNotNoHeadroom() {
        // No lines seeded for Kenya Trees at all.
        AmaizeAnalyzeHeadroom.Result res = run(req('Trees', 'Kenya', 2027));
        System.assertEquals(false, res.found);
        System.assert(res.summary.contains('No qualifying Budget Line records'), res.summary);
        System.assert(!res.summary.containsIgnoreCase('next year'), res.summary);
    }

    // Test 6 — an explicit multi-year range (partOfRange) suppresses the per-year lookahead.
    @isTest
    static void partOfRangeSuppressesLookahead() {
        treesLine('2027', -500000, 1000000);   // overfunded
        treesLine('2028', -800000, 100000);    // available

        Test.startTest();
        AmaizeAnalyzeHeadroom.Request r = req('Trees', 'Kenya', 2027);
        r.partOfRange = true;
        AmaizeAnalyzeHeadroom.Result res = run(r);
        Test.stopTest();

        System.assert(res.summary.contains('overfunded by'), res.summary);
        System.assert(!res.summary.contains('next year with available Headroom'),
            'range calls compose their own year-by-year answer: ' + res.summary);
    }

    // Test 7 — service helper: returns the first future year with room, skipping earlier tight years.
    @isTest
    static void findNextAvailableYearReturnsEarliest() {
        treesLine('2027', -500000, 1000000);   // overfunded (requested)
        treesLine('2028', -500000, 1000000);   // overfunded
        treesLine('2029', -900000, 200000);    // available +700K

        Test.startTest();
        HeadroomService.NextAvailableYear n =
            new HeadroomService().findNextAvailableYear('Trees', 'Kenya', '2027');
        Test.stopTest();

        System.assertEquals(true, n.found);
        System.assertEquals('2029', n.year);
        System.assertEquals(700000, n.availableHeadroom);
    }

    // Test 9 — service helper: no future room => found=false, records the years it searched.
    @isTest
    static void findNextAvailableYearReportsNone() {
        treesLine('2027', -500000, 1000000);
        treesLine('2028', -500000, 1000000);
        treesLine('2029', -500000, 1000000);

        Test.startTest();
        HeadroomService.NextAvailableYear n =
            new HeadroomService().findNextAvailableYear('Trees', 'Kenya', '2027');
        Test.stopTest();

        System.assertEquals(false, n.found);
        System.assertEquals(new List<String>{ '2028', '2029' }, n.yearsChecked, 'searched forward years only');
    }

    // Test 10 — the lookahead only searches years that actually have data (dynamic horizon).
    @isTest
    static void distinctFiscalYearsAreDataDriven() {
        treesLine('2027', -500000, 500000);
        treesLine('2030', -500000, 500000);

        Test.startTest();
        List<String> years = new BudgetLineSelector().distinctFiscalYears('Kenya');
        Test.stopTest();

        System.assertEquals(new List<String>{ '2027', '2030' }, years, 'ascending, only years with data');
    }

    // Read-only.
    @isTest
    static void lookaheadPerformsNoDml() {
        treesLine('2027', -500000, 1000000);
        treesLine('2028', -800000, 100000);
        Test.startTest();
        new HeadroomService().findNextAvailableYear('Trees', 'Kenya', '2027');
        System.assertEquals(0, Limits.getDmlStatements(), 'lookahead must never write data');
        Test.stopTest();
    }
}
