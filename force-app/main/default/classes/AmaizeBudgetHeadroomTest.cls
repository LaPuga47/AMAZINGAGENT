/**
 * Drift-guard test for AmaizeBudgetHeadroom.
 *
 * AmaizeBudgetHeadroom.securedHeadroom()/statusFor() are hand-written Apex meant to
 * mirror the org's own Budget_Line__c.Secured_Headroom__c / Headroom_status__c
 * declarative formulas EXACTLY. This test proves that by inserting one isolated
 * Budget_Line__c, reading back the ORG'S OWN formula values, and asserting our Apex
 * produces the identical result. If Finance ever edits either formula, this test
 * (not just intuition) will catch the drift.
 */
@isTest
private class AmaizeBudgetHeadroomTest {

    @isTest
    static void apexMirrorsOrgFormulasExactly() {
        Budget_Scenario__c scenario = new Budget_Scenario__c(
            Scenario_Type__c = 'Final Budget',
            Effective_Date__c = Date.newInstance(2027, 1, 1),
            External_Key__c = 'AMAIZE-DRIFT-GUARD-SCENARIO',
            Is_Current_Scenario__c = false,
            Fiscal_Year__c = '2027');
        insert scenario;

        Budget_Line__c line = new Budget_Line__c(
            Budget_Scenario__c = scenario.Id,
            Country__c = 'Kenya', BusinessUnit__c = 'Technology',
            Fiscal_Year__c = '2027', Budget_Amount__c = -1234500, Secured_Funding__c = 987600);
        insert line;

        Budget_Line__c fromOrg = [
            SELECT Budget_Amount__c, Secured_Funding__c, Secured_Headroom__c, Headroom_status__c
            FROM Budget_Line__c
            WHERE Id = :line.Id
        ];

        Decimal apexHeadroom = AmaizeBudgetHeadroom.securedHeadroom(
            fromOrg.Budget_Amount__c, fromOrg.Secured_Funding__c);
        String apexStatus = AmaizeBudgetHeadroom.statusFor(apexHeadroom);

        System.assertEquals(fromOrg.Secured_Headroom__c, apexHeadroom,
            'AmaizeBudgetHeadroom.securedHeadroom() must equal the org\'s Secured_Headroom__c formula');
        System.assertEquals(fromOrg.Headroom_status__c, apexStatus,
            'AmaizeBudgetHeadroom.statusFor() must equal the org\'s Headroom_status__c formula');
    }

    @isTest
    static void thresholdsMatchTheOrgFormulaAtTheBoundaries() {
        // Boundary values per the org formula:
        //   >= 250000 -> "Headroom Available"; >= 0 -> "Some Headroom Available"; else "Headroom Unavailable".
        System.assertEquals('Headroom Available', AmaizeBudgetHeadroom.statusFor(250000));
        System.assertEquals('Some Headroom Available', AmaizeBudgetHeadroom.statusFor(249999.99));
        System.assertEquals('Some Headroom Available', AmaizeBudgetHeadroom.statusFor(0));
        System.assertEquals('Headroom Unavailable', AmaizeBudgetHeadroom.statusFor(-0.01));
    }

    @isTest
    static void budgetCostFlipsTheStoredNegativeSign() {
        System.assertEquals(500000, AmaizeBudgetHeadroom.budgetCost(-500000));
        System.assertEquals(0, AmaizeBudgetHeadroom.budgetCost(null));
    }
}