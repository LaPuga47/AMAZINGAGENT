/**
 * CompetingGrantsServiceTest — governed competing-grants analysis:
 * - cross-agent CONSISTENCY: same scope -> identical governed Headroom totals + BL count as
 *   Headroom Analysis (the mandatory alignment test).
 * - full-population allocation retrieval, exposure grouped once per Opportunity across lines.
 * - governed zero / not-configured / none / needs-info states.
 * Allocations are created inside tests (the chain is SOQL-heavy).
 */
@isTest
private class CompetingGrantsServiceTest {

    @TestSetup
    static void setup() {
        Budget_Scenario__c s = HeadroomTestData.makeCurrentScenario();
        // Two Core Program - KE lines (the governed population must include BOTH).
        HeadroomTestData.makeLine(s.Id, 'Kenya', 'Core Program - KE', 'N/A', 'Extension', 'N/A', 'N/A',
            -1000000, 300000, 100000, 100000);
        HeadroomTestData.makeLine(s.Id, 'Kenya', 'Core Program - KE', 'N/A', 'Field Operations', 'N/A', 'N/A',
            -500000, 100000, 0, 0);
    }

    // MANDATORY: Headroom Analysis and Competing Grants resolve the identical governed scope.
    @isTest
    static void headroomTotalsMatchHeadroomAnalysis() {
        Test.startTest();
        HeadroomAggregate h = new HeadroomService().aggregate('Core Program', 'Kenya', '2027');
        CompetingGrantsResult c = new CompetingGrantsService().analyze('Core Program', 'Kenya', '2027');
        Test.stopTest();

        System.assertEquals(HeadroomAggregate.State.FOUND, h.state);
        System.assertEquals(CompetingGrantsResult.Status.FOUND, c.status);
        System.assertEquals(h.budgetLinesIncluded, c.budgetLineCount, 'Same Budget Line count');
        System.assertEquals(h.budgetAmount, c.budgetAmount, 'Same Budget Amount');
        System.assertEquals(h.securedFunding, c.securedFunding);
        System.assertEquals(h.likelyFunding, c.likelyFunding);
        System.assertEquals(h.pipelineFunding, c.pipelineFunding);
        System.assertEquals(h.forecastFunding, c.forecastFunding);
        System.assertEquals(h.securedHeadroom, c.securedHeadroom, 'Same Secured Headroom');
        System.assertEquals(h.forecastHeadroom, c.forecastHeadroom, 'Same Forecast Headroom');
        System.assertEquals(h.headroomStatus, c.headroomStatus);
    }

    @isTest
    static void aggregatesAllQualifyingLines() {
        CompetingGrantsResult c = new CompetingGrantsService().analyze('Core Program', 'Kenya', '2027');
        System.assertEquals(2, c.budgetLineCount, 'Both Core Program - KE lines participate');
        System.assertEquals(1500000, c.budgetAmount);   // 1.0M + 0.5M
        System.assertEquals(1100000, c.securedHeadroom); // 0.7M + 0.4M
    }

    @isTest
    static void sumsExposureOnceByOpportunityAcrossLines() {
        List<Id> lineIds = new List<Id>();
        for (Budget_Line__c bl : [SELECT Id FROM Budget_Line__c WHERE BusinessUnit__c = 'Core Program - KE']) {
            lineIds.add(bl.Id);
        }
        // One opportunity allocated $200k to EACH of the two lines (Pipeline).
        HeadroomTestData.makeOppAllocations('Pipeline', lineIds, 200000, 'Kenya', 'Core Program - KE');

        Test.startTest();
        CompetingGrantsResult c = new CompetingGrantsService().analyze('Core Program', 'Kenya', '2027');
        Test.stopTest();

        System.assertEquals(1, c.grants.size(), 'One opportunity, counted once');
        CompetingGrant g = c.grants[0];
        System.assertEquals(400000, g.allocatedAmount, 'Exposure summed across both lines (2 x 200k)');
        System.assertEquals(2, g.allocationCount);
        System.assertEquals(2, g.budgetLineIds.size(), 'Exposure spans two budget lines');
        System.assertEquals(400000, c.combinedCompeting);
    }

    @isTest
    static void unrestrictedIsZeroNoCompetition() {
        CompetingGrantsResult c = new CompetingGrantsService().analyze('Unrestricted', 'Kenya', '2027');
        System.assertEquals(CompetingGrantsResult.Status.ZERO, c.status);
    }

    @isTest
    static void miscellaneousNotConfigured() {
        CompetingGrantsResult c = new CompetingGrantsService().analyze('Miscellaneous', 'Kenya', '2027');
        System.assertEquals(CompetingGrantsResult.Status.NOT_CONFIGURED, c.status);
    }

    @isTest
    static void noQualifyingLinesIsNone() {
        CompetingGrantsResult c = new CompetingGrantsService().analyze('Trees', 'Kenya', '2027');
        System.assertEquals(CompetingGrantsResult.Status.NONE, c.status);
    }

    @isTest
    static void missingCountryNeedsInfo() {
        CompetingGrantsResult c = new CompetingGrantsService().analyze('Core Program', null, '2027');
        System.assertEquals(CompetingGrantsResult.Status.NEEDS_INFO, c.status);
    }
}
