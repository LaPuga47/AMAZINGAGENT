/**
 * HeadroomServiceTest — end-to-end coverage of the Budget-Line-first analysis engine.
 *
 * Scenario map (from the design brief):
 *   #1 exact match on all dimensions          -> exactAllDimensions_found
 *   #2 minimum dimensions, single line        -> minimumDimensions_singleMatch
 *   #3-#6 Sub/Dept/CostType/CostCategory = N/A -> naDimensions_treatedAsRealValue
 *   #7 multiple matches -> clarification       -> multipleMatches_ambiguous
 *   #8 no Budget Line matches                  -> noMatch_notFound
 *   #9 allocation directly references line      -> directAllocations_found
 *   #10 allocation via approved Match Key       -> matchKeyAllocation_found
 *   #11 Secured/Likely/Pipeline distinguished   -> allocationBreakdown_byType
 *   #12 negative headroom (over-allocation)     -> negativeHeadroom
 *   #13 zero headroom                           -> zeroHeadroom
 *   #14 positive headroom                       -> positiveHeadroom
 *   #15 portfolio ranking                       -> portfolio_ranksByHeadroom / overAllocated
 *   #16 no fiscal year                          -> missingFiscalYear_needsInfo
 *   #17 no country                              -> missingCountry_needsInfo
 *   #18 no associated allocations               -> noAllocations_sourceNone
 *   #19 missing financial data                  -> missingFinancialData_noError
 */
@isTest
private class HeadroomServiceTest {

    @TestSetup
    static void setup() {
        Budget_Scenario__c s = HeadroomTestData.makeCurrentScenario();

        // Kenya / Core Program — three lines differing ONLY by Cost Category (ambiguity).
        HeadroomTestData.makeLine(s.Id, 'Kenya', 'Core Program', 'N/A', 'N/A', 'N/A', 'N/A',
            -1000000, 300000, 100000, 100000);                 // forecast +500k, Headroom Available
        HeadroomTestData.makeLine(s.Id, 'Kenya', 'Core Program', 'N/A', 'N/A', 'N/A', 'Salary',
            -500000, 100000, 0, 0);                            // forecast +400k
        HeadroomTestData.makeLine(s.Id, 'Kenya', 'Core Program', 'N/A', 'N/A', 'N/A', 'Operations',
            -500000, 100000, 0, 0);                            // forecast +400k

        // Single-match lines.
        HeadroomTestData.makeLine(s.Id, 'Kenya', 'Field Building', 'N/A', 'N/A', 'N/A', 'N/A',
            -500000, 400000, 200000, 100000);                  // forecast -200k (over-allocated)
        HeadroomTestData.makeLine(s.Id, 'Kenya', 'Business Operations', 'N/A', 'N/A', 'N/A', 'N/A',
            -600000, 300000, 200000, 100000);                  // forecast 0
        HeadroomTestData.makeLine(s.Id, 'Rwanda', 'Farm Input Sales', 'N/A', 'N/A', 'N/A', 'N/A',
            -2000000, 500000, 0, 0);                           // forecast +1.5M
        HeadroomTestData.makeLine(s.Id, 'Kenya', 'Capital Expenditures', 'N/A', 'N/A', 'N/A', 'N/A',
            -500000, null, null, null);                        // missing funding data (funding fields empty)
        // Allocations are created inside the tests that need them (keeps this setup light
        // — the DLRS trigger + org flows on the allocation chain are SOQL-heavy).
    }

    private static BudgetLineDimensions dims(String country, String bu, String fy,
            String sub, String dept, String ct, String cc) {
        BudgetLineDimensions d = new BudgetLineDimensions();
        d.country = country; d.businessUnit = bu; d.fiscalYear = fy;
        d.subUnit = sub; d.department = dept; d.costType = ct; d.costCategory = cc;
        return d;
    }

    // #1 / #3-#6
    @isTest
    static void exactAllDimensions_found() {
        HeadroomAnalysis a = new HeadroomService().analyze(
            dims('Kenya', 'Core Program', '2027', 'N/A', 'N/A', 'N/A', 'N/A'));
        System.assertEquals(HeadroomAnalysis.Status.FOUND, a.status);
        System.assertEquals('N/A', a.line.Cost_Category__c, 'Should resolve the all-N/A line, not a Salary/Operations one');
        System.assertEquals('Headroom Available', a.line.Headroom_status__c);
    }

    // #3-#6 — N/A is a real value, not "missing".
    @isTest
    static void naDimensions_treatedAsRealValue() {
        BudgetLineDimensions d = dims('Kenya', 'Core Program', '2027', 'N/A', 'N/A', 'N/A', 'N/A').normalize();
        System.assertEquals('N/A', d.subUnit);
        System.assertEquals('N/A', d.department);
        System.assertEquals('N/A', d.costType);
        System.assertEquals('N/A', d.costCategory);
        System.assert(d.hasAllSevenDimensions(), 'N/A dimensions count as supplied');
    }

    // #2
    @isTest
    static void minimumDimensions_singleMatch() {
        HeadroomAnalysis a = new HeadroomService().analyze(
            dims('Kenya', 'Field Building', '2027', null, null, null, null));
        System.assertEquals(HeadroomAnalysis.Status.FOUND, a.status, 'One line for this country+BU -> proceed');
        System.assertEquals('Field Building', a.line.BusinessUnit__c);
    }

    // #7
    @isTest
    static void multipleMatches_ambiguous() {
        HeadroomAnalysis a = new HeadroomService().analyze(
            dims('Kenya', 'Core Program', '2027', null, null, null, null));
        System.assertEquals(HeadroomAnalysis.Status.AMBIGUOUS, a.status);
        System.assertEquals(3, a.candidates.size());
        System.assertEquals(1, a.distinguishingDimensions.size(), 'They differ only by Cost Category');
        System.assert(a.distinguishingDimensions[0].startsWith('Cost Category:'),
            'Distinguishing dimension should be Cost Category: ' + a.distinguishingDimensions);
    }

    // #8
    @isTest
    static void noMatch_notFound() {
        HeadroomAnalysis a = new HeadroomService().analyze(
            dims('Tanzania', 'Core Program', '2027', 'N/A', 'N/A', 'N/A', 'N/A'));
        System.assertEquals(HeadroomAnalysis.Status.NOT_FOUND, a.status);
    }

    // #16
    @isTest
    static void missingFiscalYear_needsInfo() {
        HeadroomAnalysis a = new HeadroomService().analyze(
            dims('Kenya', 'Core Program', null, null, null, null, null));
        System.assertEquals(HeadroomAnalysis.Status.NEEDS_INFO, a.status);
        System.assert(a.missingDimensions.contains('fiscal year'), a.missingDimensions.toString());
    }

    // #17
    @isTest
    static void missingCountry_needsInfo() {
        HeadroomAnalysis a = new HeadroomService().analyze(
            dims(null, 'Core Program', '2027', null, null, null, null));
        System.assertEquals(HeadroomAnalysis.Status.NEEDS_INFO, a.status);
        System.assert(a.missingDimensions.contains('country'), a.missingDimensions.toString());
    }

    // #12
    @isTest
    static void negativeHeadroom() {
        HeadroomAnalysis a = new HeadroomService().analyze(
            dims('Kenya', 'Field Building', '2027', 'N/A', 'N/A', 'N/A', 'N/A'));
        System.assertEquals(HeadroomAnalysis.Status.FOUND, a.status);
        System.assertEquals(-200000, a.line.Forecast_Headroom__c, 'Over-allocated is valid, not an error');
    }

    // #13
    @isTest
    static void zeroHeadroom() {
        HeadroomAnalysis a = new HeadroomService().analyze(
            dims('Kenya', 'Business Operations', '2027', 'N/A', 'N/A', 'N/A', 'N/A'));
        System.assertEquals(HeadroomAnalysis.Status.FOUND, a.status);
        System.assertEquals(0, a.line.Forecast_Headroom__c);
    }

    // #14
    @isTest
    static void positiveHeadroom() {
        HeadroomAnalysis a = new HeadroomService().analyze(
            dims('Rwanda', 'Farm Input Sales', '2027', 'N/A', 'N/A', 'N/A', 'N/A'));
        System.assertEquals(HeadroomAnalysis.Status.FOUND, a.status);
        System.assertEquals(1500000, a.line.Forecast_Headroom__c);
    }

    // #19 — funding fields empty: read as zero, not an error.
    @isTest
    static void missingFinancialData_noError() {
        HeadroomAnalysis a = new HeadroomService().analyze(
            dims('Kenya', 'Capital Expenditures', '2027', 'N/A', 'N/A', 'N/A', 'N/A'));
        System.assertEquals(HeadroomAnalysis.Status.FOUND, a.status);
        System.assertEquals(0, AmaizeBudgetHeadroom.nz(a.line.Secured_Funding__c),
            'Empty secured funding must read as zero');
        System.assertEquals(500000, a.line.Forecast_Headroom__c,
            'Headroom still computes with empty funding (budget 500k - 0)');
    }

    // #9 + #11 — direct allocations, Secured/Likely/Pipeline distinguished.
    @isTest
    static void directAllocations_breakdownByType() {
        Id scenarioId = [SELECT Id FROM Budget_Scenario__c WHERE Is_Current_Scenario__c = true LIMIT 1].Id;
        Budget_Line__c line = HeadroomTestData.makeLine(scenarioId, 'Kenya', 'Core Program - KE',
            'N/A', 'N/A', 'N/A', 'N/A', -1000000, 0, 0, 0);
        HeadroomTestData.makeAllocations(new List<HeadroomTestData.AllocSpec>{
            new HeadroomTestData.AllocSpec('Secured', 500000),
            new HeadroomTestData.AllocSpec('Likely', 300000),
            new HeadroomTestData.AllocSpec('Pipeline', 100000)
        }, line.Id, 'Kenya', 'Core Program - KE');

        Test.startTest();
        HeadroomAnalysis a = new HeadroomService().analyze(
            dims('Kenya', 'Core Program - KE', '2027', 'N/A', 'N/A', 'N/A', 'N/A'));
        Test.stopTest();

        System.assertEquals(HeadroomAnalysis.Status.FOUND, a.status);
        System.assertEquals('direct', a.allocationSource);
        System.assertEquals(3, a.allocations.totalCount);
        System.assertEquals(500000, a.allocations.securedTotal);
        System.assertEquals(300000, a.allocations.likelyTotal);
        System.assertEquals(100000, a.allocations.pipelineTotal);
        System.assertEquals(1, a.allocations.securedCount);
        System.assertEquals(1, a.allocations.likelyCount);
        System.assertEquals(1, a.allocations.pipelineCount);
    }

    // #18
    @isTest
    static void noAllocations_sourceNone() {
        HeadroomAnalysis a = new HeadroomService().analyze(
            dims('Kenya', 'Business Operations', '2027', 'N/A', 'N/A', 'N/A', 'N/A'));
        System.assertEquals(HeadroomAnalysis.Status.FOUND, a.status);
        System.assertEquals('none', a.allocationSource);
        System.assertEquals(0, a.allocations.totalCount);
    }

    // #10 — allocation resolves through the approved Match Key (built in-method for ordering).
    @isTest
    static void matchKeyAllocation_found() {
        Id scenarioId = [SELECT Id FROM Budget_Scenario__c WHERE Is_Current_Scenario__c = true LIMIT 1].Id;

        // Allocation created before its Budget Line exists -> left unlinked by the flow.
        HeadroomTestData.makeAllocation('Secured', 250000, null,
            'Kenya', 'Core Program - KE', 'N/A', 'N/A', 'N/A', 'N/A');
        HeadroomTestData.makeLine(scenarioId, 'Kenya', 'Core Program - KE',
            'N/A', 'N/A', 'N/A', 'N/A', -900000, 100000, 0, 0);

        Test.startTest();
        HeadroomAnalysis a = new HeadroomService().analyze(
            dims('Kenya', 'Core Program - KE', '2027', 'N/A', 'N/A', 'N/A', 'N/A'));
        Test.stopTest();

        System.assertEquals(HeadroomAnalysis.Status.FOUND, a.status);
        System.assertEquals('match-key', a.allocationSource, 'Should resolve via approved Match Key');
        System.assertEquals(1, a.allocations.totalCount);
        System.assertEquals(250000, a.allocations.securedTotal);
    }

    // #15
    @isTest
    static void portfolio_ranksByHeadroom() {
        List<Budget_Line__c> ranked = new HeadroomService().rankPortfolio('Kenya', '2027', 'most headroom');
        System.assert(!ranked.isEmpty(), 'Kenya should have lines with headroom');
        // Highest forecast headroom first; none negative or zero in a "most headroom" ranking.
        System.assertEquals(500000, ranked[0].Forecast_Headroom__c, 'Biggest room first');
        for (Budget_Line__c bl : ranked) {
            System.assert(bl.Forecast_Headroom__c > 0, 'Over-allocated/zero lines excluded from most-headroom');
        }
    }

    // #15 (over-allocation view)
    @isTest
    static void portfolio_overAllocatedOnly() {
        List<Budget_Line__c> ranked = new HeadroomService().rankPortfolio('Kenya', '2027', 'over-allocated');
        System.assertEquals(1, ranked.size(), 'Only Field Building is over-allocated');
        System.assertEquals('Field Building', ranked[0].BusinessUnit__c);
        System.assert(ranked[0].Forecast_Headroom__c < 0);
    }
}
