/**
 * BudgetLineScopeResolver — the single, shared resolver that turns a user's request (a standard
 * Headroom program, an explicit Budget Line dimension value, or both) into the Budget Line
 * FILTER to aggregate. Headroom Analysis and Competing Grants Analysis both consume it, so an
 * explicit dimension such as "Crop Insurance" resolves to the SAME Budget Line population in
 * either sub-agent.
 *
 * Modes:
 *   PROGRAM             — a standard Headroom category (Core Program, Trees, ...).
 *   DIMENSION           — an explicit lower-level value (Cost Category / Department / Cost Type /
 *                         Sub-Unit / Business Unit), auto-detected or named.
 *   PROGRAM_PLUS_DIMENSION — a standard program, then segmented by an explicit dimension.
 *
 * It never invents a mapping: a dimension value is matched exactly (case/space-normalized) against
 * the real Budget Line fields, and it reports AMBIGUOUS (value in >1 dimension) or NOT_FOUND
 * (value in no dimension) rather than guessing. No DML.
 */
public with sharing class BudgetLineScopeResolver {

    public enum State { FOUND, ZERO, NOT_CONFIGURED, NEEDS_INFO, AMBIGUOUS, NOT_FOUND }

    public class Scope {
        public State state;
        public String mode;                 // PROGRAM / DIMENSION / PROGRAM_PLUS_DIMENSION
        public String label;                // "Crop Insurance" / "Core Program" / "Core Program (Crop Insurance)"
        public String country;
        public String fiscalYear;
        public BudgetLineDimensions dimensions;   // the filter to aggregate (null unless FOUND)
        public String dimensionValue;             // the primary dimension value, when in dimension mode
        public List<String> candidateDimensions = new List<String>();  // set on AMBIGUOUS
        public List<String> missing = new List<String>();              // set on NEEDS_INFO
    }

    /**
     * Resolve a scope. `country` and `fiscalYear` must already be trimmed/defaulted by the caller
     * (fiscalYear defaults to the current scenario). `lines` is used to auto-detect a dimension.
     */
    public static Scope resolve(String program, String country, String fiscalYear,
            String dimName, String dimValue, String dim2Name, String dim2Value, IBudgetLineSelector lines) {
        Scope s = new Scope();
        s.country = country;
        s.fiscalYear = fiscalYear;

        Boolean hasProgram = String.isNotBlank(program);
        Boolean hasDimension = String.isNotBlank(dimValue) || String.isNotBlank(dim2Value);
        if (!hasProgram && !hasDimension) {
            s.missing.add('a program or a Budget Line dimension');
            s.state = State.NEEDS_INFO;
            return s;
        }

        BudgetLineDimensions d = new BudgetLineDimensions();
        d.country = country;
        d.fiscalYear = fiscalYear;
        String progLabel = null;

        if (hasProgram) {
            HeadroomCategoryResolver.Rule rule = HeadroomCategoryResolver.resolve(program);
            s.label = rule.label;
            if (rule.mode == HeadroomCategoryResolver.Mode.ZERO) { s.state = State.ZERO; return s; }
            if (rule.mode == HeadroomCategoryResolver.Mode.NOT_CONFIGURED) { s.state = State.NOT_CONFIGURED; return s; }
            d.businessUnit = rule.businessUnitBase;
            d.department = rule.department;
            progLabel = rule.label;
        }

        List<String> appliedValues = new List<String>();
        List<String> dimNames = new List<String>{ dimName, dim2Name };
        List<String> dimValues = new List<String>{ dimValue, dim2Value };
        for (Integer i = 0; i < 2; i++) {
            String val = dimValues[i];
            if (String.isBlank(val)) { continue; }
            String field = resolveDimField(dimNames[i], val, country, fiscalYear, s, lines);
            if (s.state == State.AMBIGUOUS || s.state == State.NOT_FOUND) {
                s.dimensionValue = val.trim();
                return s;
            }
            applyDimension(d, field, val.trim());
            appliedValues.add(val.trim());
        }

        String dimLabel = appliedValues.isEmpty() ? null : String.join(appliedValues, ' + ');
        if (!appliedValues.isEmpty()) { s.dimensionValue = appliedValues[0]; }
        s.label = (progLabel != null && dimLabel != null) ? progLabel + ' (' + dimLabel + ')'
            : (progLabel != null ? progLabel : dimLabel);
        s.mode = (progLabel != null && dimLabel != null) ? 'PROGRAM_PLUS_DIMENSION'
            : (progLabel != null ? 'PROGRAM' : 'DIMENSION');
        s.dimensions = d.normalize();
        s.state = State.FOUND;
        return s;
    }

    /** Map a dimension value to its Budget Line field; auto-detect when the dimension name is blank/unknown. */
    private static String resolveDimField(String dimName, String value, String country, String fy,
            Scope s, IBudgetLineSelector lines) {
        if (String.isNotBlank(dimName)) {
            String mapped = mapDimName(dimName);
            if (mapped != null) { return mapped; }   // explicit, recognized dimension name
        }
        Set<String> matches = lines.dimensionsContaining(value, country, fy);
        if (matches.isEmpty()) { s.state = State.NOT_FOUND; return null; }
        if (matches.size() == 1) { return mapDimName(new List<String>(matches)[0]); }
        // Value lives in more than one supported dimension — do not guess; ask which was meant.
        s.state = State.AMBIGUOUS;
        s.candidateDimensions = orderCandidates(matches);
        return null;
    }

    private static String mapDimName(String name) {
        String n = name == null ? '' : name.trim().toLowerCase().replace('-', ' ');
        if (n == 'department' || n == 'dept') { return 'department'; }
        if (n == 'cost category' || n == 'costcategory' || n == 'category') { return 'costCategory'; }
        if (n == 'cost type' || n == 'costtype') { return 'costType'; }
        if (n == 'sub unit' || n == 'subunit' || n == 'sub' || n == 'sub-unit') { return 'subUnit'; }
        if (n == 'business unit' || n == 'businessunit' || n == 'bu') { return 'businessUnit'; }
        return null;
    }

    private static void applyDimension(BudgetLineDimensions d, String field, String value) {
        if (field == 'department') { d.department = value; }
        else if (field == 'costCategory') { d.costCategory = value; }
        else if (field == 'costType') { d.costType = value; }
        else if (field == 'subUnit') { d.subUnit = value; }
        else if (field == 'businessUnit') { d.businessUnit = value; }
    }

    private static List<String> orderCandidates(Set<String> matches) {
        List<String> ordered = new List<String>();
        for (String dim : new List<String>{ 'Department', 'Cost Category', 'Cost Type', 'Sub-Unit' }) {
            if (matches.contains(dim)) { ordered.add(dim); }
        }
        return ordered;
    }
}
