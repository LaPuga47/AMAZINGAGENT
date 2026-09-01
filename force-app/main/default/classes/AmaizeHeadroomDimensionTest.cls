/**
 * AmaizeHeadroomDimensionTest — explicit Budget-Line dimension Headroom (Dimension Mode and
 * Program + Dimension), alongside the unchanged standard Program Mode:
 *   - Dimension Mode: filter by an explicit dimension value (auto-detected or named).
 *   - Program + Dimension: standard program population, then segmented by a dimension.
 *   - Ambiguity (value in >1 dimension) and not-found handling.
 *   - Standard categories (Market Access, Trees) keep their program rule unchanged.
 * Uses the same stored-field aggregation as program-level analysis.
 */
@isTest
private class AmaizeHeadroomDimensionTest {

    @TestSetup
    static void setup() {
        Budget_Scenario__c s = HeadroomTestData.makeCurrentScenario();   // FY2027
        // A: Core Program, Sub Field Operations Costs, Cost Type Staff Costs, Cost Category Crop Insurance.
        HeadroomTestData.makeLine(s.Id, 'Kenya', 'Core Program - KE', 'Field Operations Costs', 'Extension',
            'Staff Costs', 'Crop Insurance', -1000000, 0, 0, 0);
        // B: Farm Input Sales / Department Market Access (this is the standard Market Access population).
        HeadroomTestData.makeLine(s.Id, 'Kenya', 'Farm Input Sales - KE', 'N/A', 'Market Access',
            'Input Costs', 'Inputs', -500000, 100000, 0, 0);
        // C: Farm Input Sales / Department Trees (standard Trees population), Cost Type Input Costs.
        HeadroomTestData.makeLine(s.Id, 'Kenya', 'Farm Input Sales - KE', 'N/A', 'Trees',
            'Input Costs', 'N/A', -300000, 0, 0, 0);
        // D: Core Program with Department Market Access, Cost Type Staff Costs — NOT part of standard Market Access.
        HeadroomTestData.makeLine(s.Id, 'Kenya', 'Core Program - KE', 'N/A', 'Market Access',
            'Staff Costs', 'N/A', -400000, 0, 0, 0);
        // E + F: "Bad Debt Expense" as Cost Type (E) and as Cost Category (F) -> ambiguous value.
        HeadroomTestData.makeLine(s.Id, 'Kenya', 'Core Program - KE', 'N/A', 'Extension',
            'Bad Debt Expense', 'N/A', -200000, 0, 0, 0);
        HeadroomTestData.makeLine(s.Id, 'Kenya', 'Core Program - KE', 'N/A', 'Extension',
            'N/A', 'Bad Debt Expense', -100000, 0, 0, 0);
    }

    private static HeadroomAggregate dim(String program, String dimName, String dimValue) {
        return new HeadroomService().aggregateExplicit(program, 'Kenya', '2027', dimName, dimValue, null, null);
    }

    // 1. Dimension Mode, auto-detected Cost Category.
    @isTest
    static void cropInsuranceDimensionAutoDetected() {
        HeadroomAggregate a = dim(null, null, 'Crop Insurance');
        System.assertEquals(HeadroomAggregate.State.FOUND, a.state, 'found');
        System.assertEquals('Crop Insurance', a.category, 'label is the dimension value, not a program');
        System.assertEquals(1, a.budgetLinesIncluded);
        System.assertEquals(1000000, a.forecastHeadroom, 'budget 1M, no funding -> 1M available');
    }

    // 3 + 5. Explicit Department dimension differs from the standard Market Access program.
    @isTest
    static void explicitDepartmentDiffersFromStandardProgram() {
        HeadroomAggregate byDept = dim(null, 'Department', 'Market Access');   // Lines B + D
        System.assertEquals(HeadroomAggregate.State.FOUND, byDept.state);
        System.assertEquals(2, byDept.budgetLinesIncluded, 'department-only picks B and D');

        HeadroomAggregate program = new HeadroomService().aggregate('Market Access', 'Kenya', '2027');  // Line B only
        System.assertEquals(1, program.budgetLinesIncluded, 'standard Market Access = Farm Input Sales + Dept, only B');
    }

    // 4 + 12. Explicit Cost Type aggregates multiple qualifying lines.
    @isTest
    static void costTypeStaffCostsAggregates() {
        HeadroomAggregate a = dim(null, 'Cost Type', 'Staff Costs');   // Lines A + D
        System.assertEquals(2, a.budgetLinesIncluded);
        System.assertEquals(1400000, a.budgetAmount, 'A (1.0M) + D (0.4M) summed, not averaged');
    }

    // 6. Sub-Unit dimension.
    @isTest
    static void subUnitDimension() {
        HeadroomAggregate a = dim(null, 'Sub-Unit', 'Field Operations Costs');   // Line A
        System.assertEquals(HeadroomAggregate.State.FOUND, a.state);
        System.assertEquals(1, a.budgetLinesIncluded);
    }

    // 8 + 22. Program + Dimension: Core Program population segmented by Crop Insurance.
    @isTest
    static void programPlusDimensionSegments() {
        HeadroomAggregate a = dim('Core Program', null, 'Crop Insurance');   // Core Program lines, Cost Cat Crop Insurance -> A
        System.assertEquals(HeadroomAggregate.State.FOUND, a.state);
        System.assertEquals(1, a.budgetLinesIncluded);
        System.assertEquals('Core Program (Crop Insurance)', a.category, 'program label + segmentation');
    }

    // 9 + 23. Trees + Cost Type Input Costs.
    @isTest
    static void programPlusCostType() {
        HeadroomAggregate a = dim('Trees', 'Cost Type', 'Input Costs');   // Farm Input Sales + Trees + Input Costs -> C
        System.assertEquals(HeadroomAggregate.State.FOUND, a.state);
        System.assertEquals(1, a.budgetLinesIncluded);
        System.assertEquals('Trees (Input Costs)', a.category);
    }

    // 10. Ambiguous value present in more than one dimension -> ask, do not guess.
    @isTest
    static void ambiguousDimensionValue() {
        HeadroomAggregate a = dim(null, null, 'Bad Debt Expense');
        System.assertEquals(HeadroomAggregate.State.AMBIGUOUS, a.state);
        System.assert(a.candidateDimensions.contains('Cost Category') && a.candidateDimensions.contains('Cost Type'),
            'both candidate dimensions listed: ' + a.candidateDimensions);
    }

    // 11a. Value in no available dimension -> NOT_FOUND.
    @isTest
    static void notFoundDimensionValue() {
        HeadroomAggregate a = dim(null, null, 'Nonexistent Widget Zzz');
        System.assertEquals(HeadroomAggregate.State.NOT_FOUND, a.state);
    }

    // 11b. Program + Dimension with no overlap -> NONE (not a fabricated zero).
    @isTest
    static void programPlusDimensionNoOverlapIsNone() {
        HeadroomAggregate a = dim('Trees', null, 'Crop Insurance');   // Trees line C has Cost Cat N/A
        System.assertEquals(HeadroomAggregate.State.NONE, a.state);
    }

    // 7. Standard Trees program is unchanged by this feature.
    @isTest
    static void standardTreesProgramUnchanged() {
        HeadroomAggregate a = new HeadroomService().aggregate('Trees', 'Kenya', '2027');   // Line C
        System.assertEquals(HeadroomAggregate.State.FOUND, a.state);
        System.assertEquals('Trees', a.category);
        System.assertEquals(1, a.budgetLinesIncluded);
    }

    // Action-level: Dimension Mode renders a conversational summary; ambiguity asks; read-only.
    @isTest
    static void actionRendersDimensionModes() {
        AmaizeAnalyzeHeadroom.Request found = new AmaizeAnalyzeHeadroom.Request();
        found.country = 'Kenya'; found.fiscalYear = 2027; found.dimensionValue = 'Crop Insurance';
        AmaizeAnalyzeHeadroom.Result fr = AmaizeAnalyzeHeadroom.analyze(new List<AmaizeAnalyzeHeadroom.Request>{ found })[0];
        System.assertEquals(true, fr.found);
        System.assert(fr.summary.contains('Crop Insurance') && fr.summary.contains('available Headroom'), fr.summary);

        AmaizeAnalyzeHeadroom.Request amb = new AmaizeAnalyzeHeadroom.Request();
        amb.country = 'Kenya'; amb.fiscalYear = 2027; amb.dimensionValue = 'Bad Debt Expense';
        Test.startTest();
        AmaizeAnalyzeHeadroom.Result ar = AmaizeAnalyzeHeadroom.analyze(new List<AmaizeAnalyzeHeadroom.Request>{ amb })[0];
        Integer dml = Limits.getDmlStatements();   // measured inside the reset start/stop window
        Test.stopTest();
        System.assertEquals('AMBIGUOUS', ar.signal, ar.summary);
        System.assert(ar.summary.contains('Cost Category') && ar.summary.contains('Cost Type'), ar.summary);
        System.assertEquals(0, dml, 'read-only');
    }
}
