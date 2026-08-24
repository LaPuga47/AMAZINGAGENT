/**
 * Tests for AmaizeCheckHeadroom — the primary Headroom Check action, now reading
 * from the real Budget_Scenario__c / Budget_Line__c model.
 * Covers: Headroom Available / Some Headroom Available / Headroom Unavailable
 * statuses, the no-data branch, the base+country-suffix BusinessUnit__c rollup,
 * the alternatives ranking, competing grants sourced from Restriction__c.Business_Unit__c,
 * and bulk handling.
 */
@isTest
private class AmaizeCheckHeadroomTest {

    @TestSetup
    static void setup() {
        AmaizeTestData.makeAll();
    }

    // Helper to run a single headroom request.
    private static AmaizeCheckHeadroom.Result run(String country, String program, Integer yr) {
        AmaizeCheckHeadroom.Request req = new AmaizeCheckHeadroom.Request();
        req.country = country; req.program = program; req.year = yr;
        return AmaizeCheckHeadroom.check(new List<AmaizeCheckHeadroom.Request>{ req })[0];
    }

    @isTest
    static void availableWhenSecuredHeadroomIsHigh() {
        // Kenya Core Program: $4.2M budget - $3.1M secured = $1.1M >= $250K -> Available.
        Test.startTest();
        AmaizeCheckHeadroom.Result r = run('Kenya', 'Core Program', 2027);
        Test.stopTest();

        System.assertEquals('Headroom Available', r.signal, 'Kenya Core Program should be Available');
        System.assertEquals(true, r.found, 'A budget line should be found');
        System.assert(r.summary.startsWith('**Yes**'), 'Available summary should open with a clear bold "Yes"');
        System.assert(r.summary.contains('**Recommendation:** Go ahead'), 'Should recommend going ahead');
        System.assert(r.summary.contains('\n\n**Recommendation:**'),
            'Recommendation should sit on its own line after a blank line');
        // Available should also offer the forward path (figure-free) after the recommendation.
        System.assert(r.summary.contains('**Next:**'), 'Available should append a forward-path offer');
        System.assert(r.summary.contains('sketch a payment'),
            'Available forward path should mention building a schedule once secured');
        System.assert(r.headroomJson.contains('"signal":"Headroom Available"'), 'JSON should carry the signal');
    }

    @isTest
    static void unavailableWhenSecuredHeadroomIsNegative() {
        // Rwanda Farm Input Sales: $900K budget - $1.05M secured = -$150K -> Unavailable.
        Test.startTest();
        AmaizeCheckHeadroom.Result r = run('Rwanda', 'Farm Input Sales', 2027);
        Test.stopTest();

        System.assertEquals('Headroom Unavailable', r.signal, 'Rwanda Farm Input Sales should be Unavailable');
        System.assert(r.summary.startsWith('**No**'), 'Unavailable summary should open with a clear bold "No"');
        System.assert(r.summary.contains('already fully funded'), 'Should explain it is fully funded');
        System.assert(r.summary.contains('\n\n**Recommendation:** Hold off'),
            'Unavailable should recommend holding off, on its own line');
        System.assert(r.summary.contains('Grants Finance'), 'Unavailable should reference Grants Finance');
        // Rwanda Farm Input Sales has no Available sibling in the factory data (no other
        // Farm Input Sales Available group, no other Rwanda group), so the agent should
        // gracefully offer a wider scan rather than inventing alternatives.
        System.assert(r.summary.contains('scan the wider portfolio'),
            'With no nearby alternatives, Unavailable should offer a wider portfolio scan');
    }

    @isTest
    static void someAvailableWhenTightAndOffersSameRegionAlternative() {
        // Kenya Field Building: $1.8M budget - $1.7M secured = $100K (positive, < $250K) -> Some Available.
        Test.startTest();
        AmaizeCheckHeadroom.Result r = run('Kenya', 'Field Building', 2027);
        Test.stopTest();

        System.assertEquals('Some Headroom Available', r.signal, 'Kenya Field Building should be Some Available');
        System.assert(r.summary.startsWith('**Limited**'), 'Some Available summary should open with bold "Limited"');
        System.assert(r.summary.contains('\n\n**Recommendation:** Confirm with Grants Finance'),
            'Some Available should recommend confirming with Grants Finance, on its own line');
        // Some Available should proactively suggest a real alternative. Kenya Core Program is
        // Available and in the same country, so it should appear (tagged "same region") with
        // its real room figure.
        System.assert(r.summary.contains('Where to look instead'),
            'Some Available should append an alternatives block');
        System.assert(r.summary.contains('Core Program — Kenya'),
            'Kenya Core Program (Available) should be offered as a same-region alternative');
        System.assert(r.summary.contains('_(same region)_'),
            'A same-country, other-theme alternative should be tagged "(same region)"');
        System.assert(r.summary.contains('of room'),
            'Each alternative should show its real room figure');
    }

    @isTest
    static void unknownWhenNoBudgetLine() {
        // No Zambia/WASH budget line exists -> the agent must honestly say "I don't have
        // data" rather than invent numbers. (Canonical missing-data guardrail check.)
        Test.startTest();
        AmaizeCheckHeadroom.Result r = run('Zambia', 'WASH', 2027);
        Test.stopTest();

        System.assertEquals(false, r.found, 'No line should be found for Zambia WASH');
        System.assertEquals('UNKNOWN', r.signal, 'Signal should be UNKNOWN when no data');
        System.assert(r.summary.contains('don\'t have headroom data'),
            'Summary should say it has no data');
    }

    @isTest
    static void matchesWithoutYearWhenYearOmitted() {
        // Omitting the year should default to the current scenario's fiscal year (2027)
        // and still match on country + program.
        Test.startTest();
        AmaizeCheckHeadroom.Result r = run('Kenya', 'Core Program', null);
        Test.stopTest();
        System.assertEquals(true, r.found, 'Should match on country+program without an explicit year');
        System.assertEquals('Headroom Available', r.signal);
    }

    @isTest
    static void baseAndCountrySuffixedBusinessUnitsRollUpTogether() {
        // Finance sometimes records a program as a country-suffixed BusinessUnit__c
        // variant (e.g. "Core Program - KE") alongside the base name. A check for
        // "Core Program" in Kenya must SUM both into one combined answer.
        insert new Budget_Line__c(
            Budget_Scenario__c = AmaizeTestData.currentScenarioId(),
            Country__c = 'Kenya', BusinessUnit__c = 'Core Program - KE',
            Fiscal_Year__c = '2027', Budget_Amount__c = -100000, Secured_Funding__c = 40000);
        // This extra line alone: 100000 - 40000 = 60000 of secured headroom.

        Test.startTest();
        AmaizeCheckHeadroom.Result r = run('Kenya', 'Core Program', 2027);
        Test.stopTest();

        System.assertEquals(true, r.found);
        // Base fixture (1,100,000) + suffixed line (60,000) = 1,160,000.
        System.assert(r.headroomJson.contains('1160000'),
            'The base "Core Program" and suffixed "Core Program - KE" lines should be summed: ' + r.headroomJson);
    }

    @isTest
    static void sameThemeAlternativeLeadsOverSameRegion() {
        // Insert an Available Field Building line in ANOTHER country (Tanzania). For the
        // Kenya Field Building "Some Available" check, this same-theme line should LEAD
        // the alternatives, ahead of the same-region Kenya Core Program line. Local DML
        // only — the shared factory is left untouched so other test classes still hold.
        insert new Budget_Line__c(
            Budget_Scenario__c = AmaizeTestData.currentScenarioId(),
            Country__c = 'Tanzania', BusinessUnit__c = 'Field Building',
            Fiscal_Year__c = '2027', Budget_Amount__c = -1000000, Secured_Funding__c = 200000);
        // 1,000,000 - 200,000 = 800,000 of room -> Headroom Available.

        Test.startTest();
        AmaizeCheckHeadroom.Result r = run('Kenya', 'Field Building', 2027);
        Test.stopTest();

        System.assertEquals('Some Headroom Available', r.signal, 'Kenya Field Building should still be Some Available');
        System.assert(r.summary.contains('Field Building — Tanzania'),
            'The same-theme Tanzania Field Building line should appear as an alternative');
        // Same-theme leads: Tanzania Field Building must be listed before the same-region Kenya Core Program.
        Integer tzIdx = r.summary.indexOf('Field Building — Tanzania');
        Integer keIdx = r.summary.indexOf('Core Program — Kenya');
        System.assert(tzIdx != -1, 'Tanzania Field Building should be present');
        System.assert(keIdx == -1 || tzIdx < keIdx,
            'Same-theme alternative should be listed before the same-region one');
    }

    @isTest
    static void competingGrantProgramSourcedFromBusinessUnit() {
        // The reworked competing-grants logic sources a grant's program from
        // Restriction__c.Business_Unit__c (not Opportunity.Theme_Tag__c). Rwanda / Farm
        // Input Sales is Unavailable, and two grants carry a Rwanda / Farm Input Sales
        // restriction (Nordic's, and Greenfield's second restriction), so the verdict
        // should name the biggest one as the deal consuming the headroom. Before the
        // rework this matched on Theme_Tag__c and found nothing, so no grant was named.
        Test.startTest();
        AmaizeCheckHeadroom.Result r = run('Rwanda', 'Farm Input Sales', 2027);
        Test.stopTest();

        System.assertEquals('Headroom Unavailable', r.signal, 'Rwanda Farm Input Sales should be Unavailable');
        System.assert(r.summary.contains('thanks to'),
            'A competing grant matched via Business_Unit__c should be named: ' + r.summary);
        // Greenfield\'s $750K Rwanda / Farm Input Sales restriction is the biggest competitor.
        System.assert(r.summary.contains('Greenfield'),
            'The biggest Farm Input Sales grant in Rwanda should be surfaced: ' + r.summary);
    }

    @isTest
    static void bulkRequestsAllReturnResults() {
        // Bulk safety: three requests in one call return three results.
        List<AmaizeCheckHeadroom.Request> reqs = new List<AmaizeCheckHeadroom.Request>();
        for (String c : new List<String>{ 'Kenya', 'Rwanda', 'Kenya' }) {
            AmaizeCheckHeadroom.Request req = new AmaizeCheckHeadroom.Request();
            req.country = c; req.program = (c == 'Rwanda' ? 'Farm Input Sales' : 'Core Program'); req.year = 2027;
            reqs.add(req);
        }
        Test.startTest();
        List<AmaizeCheckHeadroom.Result> res = AmaizeCheckHeadroom.check(reqs);
        Test.stopTest();
        System.assertEquals(3, res.size(), 'Should return one result per request');
    }
}