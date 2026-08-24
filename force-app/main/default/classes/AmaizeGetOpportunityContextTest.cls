/**
 * Tests for AmaizeGetOpportunityContext — reading a grant's context by name.
 * Covers: single (country, program) match (rule 2a), no match, ambiguous (multiple)
 * grant match, single-country/multi-program (rule 2b), single-country/no-program
 * (rule 2c), and multi-country (rule 2d).
 */
@isTest
private class AmaizeGetOpportunityContextTest {

    @TestSetup
    static void setup() {
        AmaizeTestData.makeAll();
    }

    private static AmaizeGetOpportunityContext.Result run(String name) {
        AmaizeGetOpportunityContext.Request req = new AmaizeGetOpportunityContext.Request();
        req.opportunityName = name;
        return AmaizeGetOpportunityContext.getContext(new List<AmaizeGetOpportunityContext.Request>{ req })[0];
    }

    @isTest
    static void singleMatchReturnsContext() {
        // Rule 2a: a specific name resolves to one grant whose restrictions pin a single
        // country and a single program, so it returns country/program/year and found=true.
        Test.startTest();
        AmaizeGetOpportunityContext.Result r = run('Continental Dev Bank');
        Test.stopTest();

        System.assertEquals(true, r.found, 'Should find the Continental grant');
        System.assertEquals('Kenya', r.country, 'Country should be Kenya');
        System.assertEquals('Core Program - KE', r.program,
            'Program should be the country-suffixed Business_Unit__c value valid for Kenya');
        System.assertEquals(2027, r.year, 'Year should come from the close date');
    }

    @isTest
    static void noMatchAsksForClarification() {
        // An unknown name returns found=false and asks for the exact name.
        Test.startTest();
        AmaizeGetOpportunityContext.Result r = run('Nonexistent Grant XYZ');
        Test.stopTest();

        System.assertEquals(false, r.found, 'Should not find an unknown grant');
        System.assert(r.summary.contains('couldn\'t find'), 'Should say it could not find it');
    }

    @isTest
    static void ambiguousMatchAsksWhichOne() {
        // "Kenya Core Program" matches 2 open grants -> ask which one, pick none.
        Test.startTest();
        AmaizeGetOpportunityContext.Result r = run('Kenya Core Program');
        Test.stopTest();

        System.assertEquals(false, r.found, 'Ambiguous match should not auto-resolve');
        System.assert(r.summary.contains('more than one'), 'Should ask user to disambiguate');
    }

    @isTest
    static void multiCountryGrantAsksWhichCountry() {
        // "Greenfield" resolves to ONE grant, but its restrictions span Kenya + Rwanda,
        // so we must not guess a country — we list them and ask the RM to pick.
        Test.startTest();
        AmaizeGetOpportunityContext.Result r = run('Greenfield');
        Test.stopTest();

        System.assertEquals(false, r.found, 'A multi-country grant should not auto-resolve a country');
        System.assertEquals(null, r.country, 'No single country should be chosen');
        System.assert(r.summary.containsIgnoreCase('more than one country'),
            'Should ask which country: ' + r.summary);
        // Both eligible countries should be offered.
        System.assert(r.summary.contains('Kenya') && r.summary.contains('Rwanda'),
            'Should list both eligible countries: ' + r.summary);
    }

    @isTest
    static void multiProgramGrantAsksWhichProgram() {
        // Rule 2b: "Twin Program Kenya" resolves to ONE grant in ONE country (Kenya) but
        // spans two specific programs (Core Program + Field Building). We must return the
        // country, leave program null, and ask which program to check.
        Test.startTest();
        AmaizeGetOpportunityContext.Result r = run('Twin Program Kenya');
        Test.stopTest();

        System.assertEquals(false, r.found, 'A multi-program grant should not auto-resolve a program');
        System.assertEquals('Kenya', r.country, 'The single eligible country should still be returned');
        System.assertEquals(null, r.program, 'No single program should be chosen');
        System.assert(r.summary.containsIgnoreCase('more than one program'),
            'Should ask which program: ' + r.summary);
        System.assert(r.summary.contains('Core Program') && r.summary.contains('Field Building'),
            'Should list both eligible programs: ' + r.summary);
    }

    @isTest
    static void noProgramGrantAsksWhichProgram() {
        // Rule 2c: "No Purpose Kenya" resolves to ONE grant in ONE country (Kenya) whose
        // only restriction carries the "No Purpose Restriction" sentinel — no specific
        // program. We return the country, leave program null, and ask which program to
        // check (offering a scan of all of the country's programs).
        Test.startTest();
        AmaizeGetOpportunityContext.Result r = run('No Purpose Kenya');
        Test.stopTest();

        System.assertEquals(false, r.found, 'A no-program grant should not auto-resolve a program');
        System.assertEquals('Kenya', r.country, 'The single eligible country should still be returned');
        System.assertEquals(null, r.program, 'No program should be chosen when the grant carries no program restriction');
        System.assert(r.summary.contains('no specific program restriction'),
            'Should explain there is no program restriction: ' + r.summary);
        System.assert(r.summary.containsIgnoreCase('scan all of Kenya'),
            'Should offer to scan all of the country\'s programs: ' + r.summary);
    }
}