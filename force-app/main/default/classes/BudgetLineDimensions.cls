/**
 * BudgetLineDimensions — the seven dimensions that identify a Budget_Line__c, plus
 * the normalization and minimum-information rules the Headroom analysis relies on.
 *
 * A Budget Line is identified by: Fiscal Year, Country, Business Unit, Sub-Unit,
 * Department, Cost Type, and Cost Category. Crucially, an explicit "N/A" is a REAL
 * value here (many Budget Lines legitimately carry N/A on Sub-Unit / Department /
 * Cost Type / Cost Category) — only a blank/absent value counts as "missing".
 *
 * Plain data holder — no SOQL, no DML.
 */
public with sharing class BudgetLineDimensions {

    public String fiscalYear;
    public String country;
    public String businessUnit;
    public String subUnit;
    public String department;
    public String costType;
    public String costCategory;

    public BudgetLineDimensions() {}

    /**
     * Return a normalized copy: every value trimmed; a value that is blank after
     * trimming becomes null (missing). "N/A" is preserved verbatim as a real value.
     */
    public BudgetLineDimensions normalize() {
        BudgetLineDimensions d = new BudgetLineDimensions();
        d.fiscalYear = clean(fiscalYear);
        d.country = clean(country);
        d.businessUnit = clean(businessUnit);
        d.subUnit = clean(subUnit);
        d.department = clean(department);
        d.costType = clean(costType);
        d.costCategory = clean(costCategory);
        return d;
    }

    /** True when all seven dimensions are present, so an exact composite-key match is possible. */
    public Boolean hasAllSevenDimensions() {
        return fiscalYear != null && country != null && businessUnit != null
            && subUnit != null && department != null && costType != null && costCategory != null;
    }

    /**
     * The hard minimum needed to attempt a reasonably specific search: Fiscal Year,
     * Country, and Business Unit. Sub-Unit is strongly preferred but handled by the
     * ambiguity path (we still search, then ask if more than one line matches).
     */
    public Boolean hasRequiredMinimum() {
        return fiscalYear != null && country != null && businessUnit != null;
    }

    /** Friendly names of the required dimensions that are still missing. */
    public List<String> missingRequired() {
        List<String> missing = new List<String>();
        if (fiscalYear == null) { missing.add('fiscal year'); }
        if (country == null) { missing.add('country'); }
        if (businessUnit == null) { missing.add('business unit'); }
        return missing;
    }

    /** Friendly "dimension value" phrases for the dimensions that WERE supplied. */
    public List<String> suppliedPhrases() {
        List<String> parts = new List<String>();
        if (fiscalYear != null) { parts.add('fiscal year ' + fiscalYear); }
        if (country != null) { parts.add('country ' + country); }
        if (businessUnit != null) { parts.add('business unit ' + businessUnit); }
        if (subUnit != null) { parts.add('sub-unit ' + subUnit); }
        if (department != null) { parts.add('department ' + department); }
        if (costType != null) { parts.add('cost type ' + costType); }
        if (costCategory != null) { parts.add('cost category ' + costCategory); }
        return parts;
    }

    private static String clean(String value) {
        if (value == null) { return null; }
        String trimmed = value.trim();
        return trimmed == '' ? null : trimmed;
    }
}
