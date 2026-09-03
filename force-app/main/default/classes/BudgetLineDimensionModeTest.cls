/**
 * BudgetLineDimensionModeTest — explicit Budget Line dimension resolution as a FIRST-CLASS
 * capability shared by BOTH Headroom Analysis and Competing Grants Analysis, through the shared
 * BudgetLineScopeResolver.
 *
 * The defect this guards against: an explicit dimension value such as "Crop Insurance" (a Cost
 * Category, not a standard Program) resolved correctly in Headroom Dimension Mode but Competing
 * Grants reported "No qualifying Budget Line records" because it routed the value through the
 * standard Program-category resolver, which does not know it. Both paths now resolve the SAME
 * qualifying Budget Line population.
 */
@isTest
private class BudgetLineDimensionModeTest {

    @TestSetup
    static void setup() {
        Budget_Scenario__c s = HeadroomTestData.makeCurrentScenario();
        // Malawi Core Program population: a Crop Insurance (Cost Category) line + an Input Costs line.
        HeadroomTestData.makeLine(s.Id, 'Malawi', 'Core Program - MW', 'N/A', 'N/A', 'N/A', 'Crop Insurance',
            -800000, 100000, 0, 0);
        HeadroomTestData.makeLine(s.Id, 'Malawi', 'Core Program - MW', 'N/A', 'N/A', 'N/A', 'Input Costs',
            -200000, 50000, 0, 0);
        // A value that lives in TWO dimensions: 'Bad Debt Expense' as a Cost Category on one line and
        // as a Cost Type on another — used to prove an ambiguous dimension value asks rather than guesses.
        HeadroomTestData.makeLine(s.Id, 'Malawi', 'Core Program - MW', 'N/A', 'N/A', 'N/A', 'Bad Debt Expense',
            -100000, 0, 0, 0);
        HeadroomTestData.makeLine(s.Id, 'Malawi', 'Core Program - MW', 'N/A', 'N/A', 'Bad Debt Expense', 'Inputs',
            -100000, 0, 0, 0);
    }

    private static Id cropLineId() {
        return [SELECT Id FROM Budget_Line__c WHERE Cost_Category__c = 'Crop Insurance' LIMIT 1].Id;
    }

    // ---- Headroom Dimension Mode (the already-working path, re-asserted on the shared resolver) ----

    @isTest
    static void headroomDimensionModeFindsCropInsurance() {
        Test.startTest();
        HeadroomAggregate h = new HeadroomService()
            .aggregateExplicit(null, 'Malawi', '2027', null, 'Crop Insurance', null, null);
        Test.stopTest();

        System.assertEquals(HeadroomAggregate.State.FOUND, h.state, 'Crop Insurance resolves in Headroom');
        System.assertEquals('Crop Insurance', h.category);
        System.assertEquals(1, h.budgetLinesIncluded, 'Only the Crop Insurance Cost Category line');
    }

    // ---- Competing Grants Dimension Mode (THE FIX) ----

    @isTest
    static void competingGrantsDimensionModeFindsCropInsurance() {
        // A grant funding the Crop Insurance line so competition can actually be surfaced.
        HeadroomTestData.makeOppAllocations('Likely', new List<Id>{ cropLineId() }, 200000, 'Malawi', 'Core Program - MW');

        Test.startTest();
        CompetingGrantsResult c = new CompetingGrantsService()
            .analyzeExplicit(null, 'Malawi', '2027', null, 'Crop Insurance', null, null);
        Test.stopTest();

        // Previously this returned NONE — the regression this test locks down.
        System.assertEquals(CompetingGrantsResult.Status.FOUND, c.status,
            'Competing Grants must resolve Crop Insurance, not report no qualifying records');
        System.assertEquals('Crop Insurance', c.category);
        System.assertEquals(1, c.budgetLineCount, 'Same single Crop Insurance line');
        System.assertEquals(1, c.grants.size(), 'The competing grant is found');
        System.assertEquals(200000, c.combinedCompeting);
    }

    // ---- Cross-agent CONSISTENCY: identical population from the SAME resolver ----

    @isTest
    static void headroomAndCompetingResolveIdenticalDimensionScope() {
        Test.startTest();
        HeadroomAggregate h = new HeadroomService()
            .aggregateExplicit(null, 'Malawi', '2027', null, 'Crop Insurance', null, null);
        CompetingGrantsResult c = new CompetingGrantsService()
            .analyzeExplicit(null, 'Malawi', '2027', null, 'Crop Insurance', null, null);
        Test.stopTest();

        System.assertEquals(h.budgetLinesIncluded, c.budgetLineCount, 'Same Budget Line count');
        System.assertEquals(h.budgetAmount, c.budgetAmount, 'Same Budget Amount');
        System.assertEquals(h.securedFunding, c.securedFunding);
        System.assertEquals(h.securedHeadroom, c.securedHeadroom, 'Same Secured Headroom');
        System.assertEquals(h.forecastHeadroom, c.forecastHeadroom, 'Same Forecast Headroom');
        System.assertEquals(h.headroomStatus, c.headroomStatus);
    }

    // ---- Program + Dimension in Competing Grants ----

    @isTest
    static void competingGrantsProgramPlusDimensionSegments() {
        Test.startTest();
        CompetingGrantsResult c = new CompetingGrantsService()
            .analyzeExplicit('Core Program', 'Malawi', '2027', null, 'Crop Insurance', null, null);
        Test.stopTest();

        System.assertEquals(CompetingGrantsResult.Status.FOUND, c.status);
        System.assertEquals('Core Program (Crop Insurance)', c.category, 'Program segmented by dimension');
        System.assertEquals(1, c.budgetLineCount, 'Narrowed from the whole Core Program to the Crop Insurance line');
    }

    // ---- Standard program logic UNCHANGED (not affected by the dimension path) ----

    @isTest
    static void standardProgramModeStillAggregatesWholePopulation() {
        Test.startTest();
        CompetingGrantsResult c = new CompetingGrantsService().analyze('Core Program', 'Malawi', '2027');
        Test.stopTest();

        System.assertEquals(CompetingGrantsResult.Status.FOUND, c.status);
        System.assertEquals('Core Program', c.category, 'Standard program label, not the dimension');
        System.assertEquals(4, c.budgetLineCount, 'All Core Program - MW lines, unsegmented');
    }

    @isTest
    static void standardProgramNoLinesIsStillNone() {
        // No Trees lines seeded — the standard program path must still report NONE, unchanged.
        CompetingGrantsResult c = new CompetingGrantsService().analyze('Trees', 'Malawi', '2027');
        System.assertEquals(CompetingGrantsResult.Status.NONE, c.status);
    }

    // ---- Ambiguity and not-found: ask / report, never guess (§7, §23) ----

    @isTest
    static void ambiguousDimensionValueAsksInCompetingGrants() {
        Test.startTest();
        CompetingGrantsResult c = new CompetingGrantsService()
            .analyzeExplicit(null, 'Malawi', '2027', null, 'Bad Debt Expense', null, null);
        Test.stopTest();

        System.assertEquals(CompetingGrantsResult.Status.AMBIGUOUS, c.status);
        System.assertEquals('Bad Debt Expense', c.dimensionValue);
        System.assert(c.candidateDimensions.contains('Cost Category') && c.candidateDimensions.contains('Cost Type'),
            'Both candidate dimensions offered: ' + c.candidateDimensions);
    }

    @isTest
    static void explicitDimensionNameSkipsAmbiguity() {
        // Naming the dimension resolves it directly even when the value exists in more than one.
        Test.startTest();
        CompetingGrantsResult c = new CompetingGrantsService()
            .analyzeExplicit(null, 'Malawi', '2027', 'Cost Type', 'Bad Debt Expense', null, null);
        Test.stopTest();

        System.assertEquals(CompetingGrantsResult.Status.FOUND, c.status, 'Explicit Cost Type resolves without asking');
        System.assertEquals(1, c.budgetLineCount, 'Only the Cost Type = Bad Debt Expense line');
    }

    @isTest
    static void notFoundDimensionValueIsReported() {
        Test.startTest();
        CompetingGrantsResult c = new CompetingGrantsService()
            .analyzeExplicit(null, 'Malawi', '2027', null, 'Nonexistent Widget', null, null);
        Test.stopTest();

        System.assertEquals(CompetingGrantsResult.Status.NOT_FOUND, c.status);
        System.assertEquals('Nonexistent Widget', c.dimensionValue);
    }

    // ---- Action wiring: the sub-agent actions expose dimension mode ----

    @isTest
    static void findCompetingGrantsActionDimensionMode() {
        HeadroomTestData.makeOppAllocations('Likely', new List<Id>{ cropLineId() }, 200000, 'Malawi', 'Core Program - MW');

        Test.startTest();
        AmaizeFindCompetingGrants.Request req = new AmaizeFindCompetingGrants.Request();
        req.country = 'Malawi'; req.fiscalYear = 2027; req.dimensionValue = 'Crop Insurance';
        AmaizeFindCompetingGrants.Result r =
            AmaizeFindCompetingGrants.find(new List<AmaizeFindCompetingGrants.Request>{ req })[0];
        Test.stopTest();

        System.assertEquals(true, r.found, 'Dimension-mode competing grants resolves via the action');
        System.assert(!r.summary.contains('No qualifying Budget Line records'),
            'Must NOT report no qualifying records: ' + r.summary);
    }

    @isTest
    static void getAllocationsActionDimensionMode() {
        HeadroomTestData.makeOppAllocations('Likely', new List<Id>{ cropLineId() }, 200000, 'Malawi', 'Core Program - MW');

        Test.startTest();
        AmaizeGetAllocations.Request req = new AmaizeGetAllocations.Request();
        req.country = 'Malawi'; req.fiscalYear = 2027; req.dimensionValue = 'Crop Insurance';
        AmaizeGetAllocations.Result r =
            AmaizeGetAllocations.get(new List<AmaizeGetAllocations.Request>{ req })[0];
        Test.stopTest();

        System.assertEquals(true, r.found);
        System.assertEquals(1, r.matchCount, 'The Crop Insurance allocation is listed');
        System.assert(r.summary.contains('/lightning/r/Allocation__c/'), 'Clickable allocation: ' + r.summary);
    }

    @isTest
    static void getAllocationsActionAmbiguousAsks() {
        Test.startTest();
        AmaizeGetAllocations.Request req = new AmaizeGetAllocations.Request();
        req.country = 'Malawi'; req.fiscalYear = 2027; req.dimensionValue = 'Bad Debt Expense';
        AmaizeGetAllocations.Result r =
            AmaizeGetAllocations.get(new List<AmaizeGetAllocations.Request>{ req })[0];
        Test.stopTest();

        System.assertEquals(false, r.found);
        System.assert(r.summary.contains('more than one Budget Line dimension'), r.summary);
    }

    // ---- Read-only ----

    @isTest
    static void dimensionModePerformsNoDml() {
        Test.startTest();
        new HeadroomService().aggregateExplicit(null, 'Malawi', '2027', null, 'Crop Insurance', null, null);
        new CompetingGrantsService().analyzeExplicit(null, 'Malawi', '2027', null, 'Crop Insurance', null, null);
        System.assertEquals(0, Limits.getDmlStatements(), 'Dimension resolution must never write data');
        Test.stopTest();
    }

    // ---- Shared resolver direct unit checks ----

    @isTest
    static void resolverNeedsInfoWhenNeitherProgramNorDimension() {
        BudgetLineScopeResolver.Scope s = BudgetLineScopeResolver.resolve(
            null, 'Malawi', '2027', null, null, null, null, new BudgetLineSelector());
        System.assertEquals(BudgetLineScopeResolver.State.NEEDS_INFO, s.state);
        System.assert(!s.missing.isEmpty());
    }

    @isTest
    static void resolverZeroCategoryShortCircuits() {
        BudgetLineScopeResolver.Scope s = BudgetLineScopeResolver.resolve(
            'Unrestricted', 'Malawi', '2027', null, null, null, null, new BudgetLineSelector());
        System.assertEquals(BudgetLineScopeResolver.State.ZERO, s.state);
    }

    @isTest
    static void resolverDimensionModeReturnsCostCategoryFilter() {
        BudgetLineScopeResolver.Scope s = BudgetLineScopeResolver.resolve(
            null, 'Malawi', '2027', null, 'Crop Insurance', null, null, new BudgetLineSelector());
        System.assertEquals(BudgetLineScopeResolver.State.FOUND, s.state);
        System.assertEquals('DIMENSION', s.mode);
        System.assertEquals('Crop Insurance', s.dimensions.costCategory, 'Resolved to the Cost Category field');
    }
}
