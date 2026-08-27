/**
 * HeadroomCategoryResolver — the governed mapping from a user's Headroom category / program
 * terminology to the Budget Line filters that define its population. This is the single
 * source of truth for the HR-001..HR-007 rules; it never guesses a mapping.
 *
 * A resolved rule says WHICH Budget Lines participate (business-unit base + optional
 * Department); the aggregation layer then sums the governed financial fields across all
 * qualifying lines. Country and Fiscal Year are applied by the caller as explicit filters.
 *
 * Business units are country-suffixed in the org ("Core Program - KE"); we resolve on the
 * base name ("Core Program") and let the Budget Line Country field be authoritative, so we
 * never rely on parsing the suffix.
 */
public with sharing class HeadroomCategoryResolver {

    public enum Mode { NORMAL, ZERO, NOT_CONFIGURED, GENERIC }

    /** A resolved governed rule for a Headroom category. */
    public class Rule {
        public String label;              // canonical category label for the response
        public Mode mode;
        public String businessUnitBase;   // e.g. "Core Program" / "Farm Input Sales" / "Systems Change"
        public String department;         // required Department filter, or null when not restricted
        public Rule(String label, Mode mode, String businessUnitBase, String department) {
            this.label = label;
            this.mode = mode;
            this.businessUnitBase = businessUnitBase;
            this.department = department;
        }
    }

    /**
     * Resolve a user-supplied category/program string to its governed rule. Recognized
     * governed categories (HR-001..HR-007) return their exact filter; the two explicitly
     * unconfigured buckets return NOT_CONFIGURED; anything else is treated as a direct
     * business-unit base match (GENERIC) — a literal filter, not a guessed category mapping.
     */
    public static Rule resolve(String program) {
        String p = normalize(program);
        if (p == '') { return null; }

        // HR-001 Core (Field) Program
        if (inSet(p, new Set<String>{
                'core program', 'core field program', 'core (field) program', 'field program' })) {
            return new Rule('Core Program', Mode.NORMAL, 'Core Program', null);
        }
        // HR-002 Rural Retail  (Farm Input Sales + Department = Rural Retail)
        if (inSet(p, new Set<String>{ 'rural retail', 'rural retail program', 'rrt' })) {
            return new Rule('Rural Retail', Mode.NORMAL, 'Farm Input Sales', 'Rural Retail');
        }
        // HR-003 Market Access (Farm Input Sales + Department = Market Access)
        if (inSet(p, new Set<String>{ 'market access', 'market access program', 'mkt' })) {
            return new Rule('Market Access', Mode.NORMAL, 'Farm Input Sales', 'Market Access');
        }
        // HR-004 Trees (Farm Input Sales + Department = Trees)
        if (inSet(p, new Set<String>{ 'trees', 'trees program', 'tre' })) {
            return new Rule('Trees', Mode.NORMAL, 'Farm Input Sales', 'Trees');
        }
        // HR-005 System Change Extension & Other Programs (Systems Change, all)
        if (inSet(p, new Set<String>{
                'system change', 'systems change', 'system change extension',
                'systems change extension', 'system change extension & other programs',
                'systems change extension & other programs' })) {
            return new Rule('System Change Extension & Other Programs', Mode.NORMAL, 'Systems Change', null);
        }
        // HR-006 Unrestricted  and  HR-007 Working Capital -> governed zero
        if (inSet(p, new Set<String>{ 'unrestricted' })) {
            return new Rule('Unrestricted', Mode.ZERO, null, null);
        }
        if (inSet(p, new Set<String>{ 'working capital' })) {
            return new Rule('Working Capital', Mode.ZERO, null, null);
        }
        // Explicitly not-yet-configured buckets
        if (inSet(p, new Set<String>{
                'other support departments', 'other support department', 'miscellaneous', 'misc' })) {
            return new Rule(titleCase(program), Mode.NOT_CONFIGURED, null, null);
        }
        // Anything else: a direct business-unit match (literal filter, not a category guess).
        return new Rule(program.trim(), Mode.GENERIC, program.trim(), null);
    }

    /**
     * Reverse mapping for portfolio analysis: given a Budget Line's Business Unit and
     * Department, return the canonical governed category label it belongs to, or null when it
     * is not part of a governed category. Mirrors the forward rules so portfolio rollups and
     * single-scope analysis stay consistent. Business unit is matched on its base name (the
     * part before the " - <country code>" suffix).
     */
    public static String categoryForBudgetLine(String businessUnit, String department) {
        String base = baseName(businessUnit);
        if (base == null) { return null; }
        if (base.equalsIgnoreCase('Core Program')) { return 'Core Program'; }
        if (base.equalsIgnoreCase('Systems Change')) { return 'System Change Extension & Other Programs'; }
        if (base.equalsIgnoreCase('Farm Input Sales')) {
            String d = department == null ? '' : department.trim();
            if (d.equalsIgnoreCase('Rural Retail')) { return 'Rural Retail'; }
            if (d.equalsIgnoreCase('Market Access')) { return 'Market Access'; }
            if (d.equalsIgnoreCase('Trees')) { return 'Trees'; }
            return null;   // Farm Input Sales under a non-governed department
        }
        return null;
    }

    /** The base business-unit name, stripping any " - <code>" country suffix. */
    public static String baseName(String businessUnit) {
        if (String.isBlank(businessUnit)) { return null; }
        String bu = businessUnit.trim();
        return bu.contains(' - ') ? bu.substringBefore(' - ').trim() : bu;
    }

    private static Boolean inSet(String p, Set<String> synonyms) {
        return synonyms.contains(p);
    }

    /** Lowercase, collapse internal whitespace, trim. */
    private static String normalize(String s) {
        if (s == null) { return ''; }
        return s.trim().toLowerCase().replaceAll('\\s+', ' ');
    }

    private static String titleCase(String s) {
        return s == null ? '' : s.trim();
    }
}
