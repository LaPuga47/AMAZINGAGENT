/**
 * AmaizeHeadroom — the single source of truth for the headroom calculation and
 * the GREEN / AMBER / RED signal rule.
 *
 * In plain terms: "headroom" is how much room is left to raise money for a program —
 * the budgeted cost minus the funding already committed. We compute it under four
 * funding scenarios and turn the pattern into one signal:
 *   GREEN = clearly positive in every scenario (a real funding gap → pitch here)
 *   RED   = clearly negative in every scenario (already over-funded → don't)
 *   AMBER = mixed, or close to zero (consult Grants Finance)
 *
 * Both AmaizeCheckHeadroom (one program at a time) and AmaizeFindPrograms (scan the
 * whole file) use this class, so the rule can never drift between them.
 */
public with sharing class AmaizeHeadroom {

    // How close to zero counts as "tight" rather than a clear gap/surplus (+/- $50K).
    public static final Decimal TIGHT_BAND = 50000;

    /** Headroom for one scenario = budgeted cost minus the restricted funding committed. */
    public static Decimal headroom(Decimal budget, Decimal restricted) {
        return nz(budget) - nz(restricted);
    }

    /**
     * Derive the overall signal from the four restricted-funding figures of a headroom row.
     *  - every scenario clearly positive  -> GREEN
     *  - every scenario clearly negative  -> RED
     *  - anything mixed or within the band -> AMBER
     */
    public static String signalFor(Decimal budget, Decimal secured, Decimal probWeighted,
            Decimal likely30, Decimal likely50) {
        List<Decimal> all = new List<Decimal>{
            headroom(budget, secured), headroom(budget, probWeighted),
            headroom(budget, likely30), headroom(budget, likely50)
        };
        Boolean allClearlyPositive = true;
        Boolean allClearlyNegative = true;
        for (Decimal h : all) {
            if (h <= TIGHT_BAND) { allClearlyPositive = false; }   // not safely above zero
            if (h >= -TIGHT_BAND) { allClearlyNegative = false; }  // not safely below zero
        }
        if (allClearlyPositive) { return 'GREEN'; }
        if (allClearlyNegative) { return 'RED'; }
        return 'AMBER';
    }

    /** Null-safe number: treat a missing currency value as zero. */
    public static Decimal nz(Decimal value) {
        return value == null ? 0 : value;
    }
}