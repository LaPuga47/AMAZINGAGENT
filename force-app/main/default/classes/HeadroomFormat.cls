/**
 * HeadroomFormat — small shared helper for rendering Budget Line headroom answers
 * in human-readable form. Keeps label/dimension wording in one place so the two
 * headroom actions (single-line analysis and portfolio ranking) read consistently.
 *
 * Read-only helper: no SOQL, no DML.
 */
public with sharing class HeadroomFormat {

    /**
     * A readable identity for a Budget Line, e.g.
     *   "FY2027 Kenya | Core Program | Extension | Staff Costs".
     * Always leads with Fiscal Year, Country, and Business Unit; appends Sub-Unit,
     * Department, Cost Type, and Cost Category only when they carry a real value
     * (blank and "N/A" are omitted to keep the label short).
     */
    public static String lineLabel(Budget_Line__c bl) {
        if (bl == null) {
            return '(unknown Budget Line)';
        }
        List<String> parts = new List<String>();
        if (bl.BusinessUnit__c != null) {
            parts.add(bl.BusinessUnit__c);
        }
        for (String value : new List<String>{
                bl.Sub__c, bl.Department__c, bl.Cost_Type__c, bl.Cost_Category__c }) {
            if (isMeaningful(value)) {
                parts.add(value);
            }
        }
        String prefix = '';
        if (bl.Fiscal_Year__c != null) { prefix += 'FY' + bl.Fiscal_Year__c + ' '; }
        if (bl.Country__c != null) { prefix += bl.Country__c; }
        if (!parts.isEmpty()) {
            prefix += (prefix == '' ? '' : ' | ') + String.join(parts, ' | ');
        }
        return prefix == '' ? '(unlabeled Budget Line)' : prefix;
    }

    /** Friendly name for a Budget_Line__c dimension field (used in clarification prompts). */
    public static String dimensionLabel(String fieldApiName) {
        Map<String, String> labels = new Map<String, String>{
            'Fiscal_Year__c' => 'Fiscal Year',
            'Country__c' => 'Country',
            'BusinessUnit__c' => 'Business Unit',
            'Sub__c' => 'Sub-Unit',
            'Department__c' => 'Department',
            'Cost_Type__c' => 'Cost Type',
            'Cost_Category__c' => 'Cost Category'
        };
        return labels.containsKey(fieldApiName) ? labels.get(fieldApiName) : fieldApiName;
    }

    /** Join phrases into natural English: "a", "a and b", "a, b, and c". */
    public static String humanJoin(List<String> items) {
        if (items == null || items.isEmpty()) { return ''; }
        if (items.size() == 1) { return items[0]; }
        if (items.size() == 2) { return items[0] + ' and ' + items[1]; }
        List<String> head = new List<String>(items);
        String last = head.remove(head.size() - 1);
        return String.join(head, ', ') + ', and ' + last;
    }

    private static Boolean isMeaningful(String value) {
        return value != null && value.trim() != '' && !value.equalsIgnoreCase('N/A');
    }
}
