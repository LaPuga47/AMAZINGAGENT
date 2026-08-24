/**
 * Shared, prompt-agnostic presentation layer for every Agent Action's
 * human-readable output. Two responsibilities:
 *
 *  1. Centralize the formatting building blocks (money, date, status/count
 *     breakdowns) so no service copy/pastes them.
 *  2. Enforce the single human-readable contract via sanitize(): agent-facing
 *     text must never contain a URL, a Lightning record path, or the platform's
 *     URL_Redacted token. Salesforce record Ids are kept out by construction
 *     (services never add an Id to text); sanitize() is the safety net that also
 *     strips any URL/Id that would otherwise appear inside a link.
 *
 * Record Ids and record URLs remain available on the structured DTOs
 * (*Summary, *SummaryResult) for a future UI (LWC) or API consumer — they are
 * simply never surfaced to the model.
 */
public inherited sharing class SummaryText {
    /** Currency-prefixed, 2-dp amount; 'N/A' when null (safe for concatenation). */
    public static String money(String currencyIso, Decimal amount) {
        return amount == null ? 'N/A' : prefix(currencyIso) + amount.setScale(2, System.RoundingMode.HALF_UP).format();
    }

    /** Currency-prefixed amount, or null when the amount is null (for "show only if present" fields). */
    public static String moneyOrNull(String currencyIso, Decimal amount) {
        return amount == null ? null : prefix(currencyIso) + amount.setScale(2, System.RoundingMode.HALF_UP).format();
    }

    /** ISO date string, or 'N/A' when null. */
    public static String dateOrNa(Date value) {
        return value == null ? 'N/A' : String.valueOf(value);
    }

    /** "Paid: 3 (USD 100), Pending: 1 (USD 50)" from parallel count/amount maps. */
    public static String statusBreakdown(String currencyIso, Map<String, Integer> counts, Map<String, Decimal> amounts) {
        if (counts == null || counts.isEmpty()) {
            return 'None';
        }
        List<String> parts = new List<String>();
        for (String st : counts.keySet()) {
            Decimal amt = amounts == null ? null : amounts.get(st);
            parts.add(st + ': ' + counts.get(st) + ' (' + money(currencyIso, amt) + ')');
        }
        return String.join(parts, ', ');
    }

    /** "Sent: 30, Responded: 20" from a count-only map. */
    public static String countBreakdown(Map<String, Integer> counts) {
        if (counts == null || counts.isEmpty()) {
            return 'None';
        }
        List<String> parts = new List<String>();
        for (String st : counts.keySet()) {
            parts.add(st + ': ' + counts.get(st));
        }
        return String.join(parts, ', ');
    }

    /**
     * The single enforcement point for the human-readable contract. Removes any
     * http/https URL, Lightning record path, the URL_Redacted token, and any
     * leftover "Link:" fragment from agent-facing text. Safe on already-clean text.
     */
    public static String sanitize(String text) {
        if (String.isBlank(text)) {
            return text;
        }
        String out = text;
        // Strip the platform's masking token (any casing).
        out = out.replaceAll('(?i)url_redacted', '');
        // Strip absolute URLs and relative Lightning record paths.
        out = out.replaceAll('https?://\\S+', '');
        out = out.replaceAll('/lightning/\\S+', '');
        // Strip any dangling "Link:" / "Record:" label plus the rest of its value on the line.
        out = out.replaceAll('(?im)[ \\t]*,?[ \\t]*(?:Link|Record Link|Record Url):[^\\n]*', '');
        // Tidy the artifacts left behind (double spaces, trailing separators).
        out = out.replaceAll('[ \\t]{2,}', ' ');
        out = out.replaceAll('(?m)[ \\t]+$', '');
        return out;
    }

    private static String prefix(String currencyIso) {
        return String.isBlank(currencyIso) ? '' : currencyIso + ' ';
    }
}