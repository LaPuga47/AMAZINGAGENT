/**
 * AmaizeBudgetHeadroom — the single source of truth for the Secured-Headroom
 * calculation and the tri-state status rule, mirrored EXACTLY from the org's own
 * declarative formulas on Budget_Line__c so Apex and the field formulas can never
 * drift apart:
 *
 *   Budget_Line__c.Secured_Headroom__c (formula) = -Budget_Amount__c - Secured_Funding__c
 *   Budget_Line__c.Headroom_status__c  (formula) =
 *       IF(Secured_Headroom__c >= 250000, "Headroom Available",
 *           IF(Secured_Headroom__c >= 0, "Some Headroom Available", "Headroom Unavailable"))
 *
 * Budget_Amount__c is stored NEGATIVE (it is an expense), so budgetCost() flips the
 * sign back to a positive figure people can read. This is the ONE place that sign
 * flip happens — both AmaizeCheckHeadroom and AmaizeFindPrograms call through here
 * so the rule can never disagree between the two actions, or with the org formula.
 */
public with sharing class AmaizeBudgetHeadroom {

    // Thresholds mirror Budget_Line__c.Headroom_status__c exactly — see class header.
    public static final Decimal SECURED_AVAILABLE = 250000;
    public static final Decimal SOME_AVAILABLE = 0;

    /** Null-safe number: treat a missing currency value as zero. */
    public static Decimal nz(Decimal value) {
        return value == null ? 0 : value;
    }

    /** Budget_Amount__c is stored negative (an expense); flip it to a positive cost. */
    public static Decimal budgetCost(Decimal sumBudgetAmount) {
        return -nz(sumBudgetAmount);
    }

    /** Mirrors Secured_Headroom__c exactly: budgeted cost minus secured funding. */
    public static Decimal securedHeadroom(Decimal sumBudgetAmount, Decimal sumSecuredFunding) {
        return budgetCost(sumBudgetAmount) - nz(sumSecuredFunding);
    }

    /** Mirrors Headroom_status__c exactly. */
    public static String statusFor(Decimal securedHeadroom) {
        if (securedHeadroom >= SECURED_AVAILABLE) {
            return 'Headroom Available';
        }
        if (securedHeadroom >= SOME_AVAILABLE) {
            return 'Some Headroom Available';
        }
        return 'Headroom Unavailable';
    }
}