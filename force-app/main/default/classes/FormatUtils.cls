/**
 * Reusable, prompt-agnostic formatting for agent-readable output. The agent
 * should surface these strings verbatim rather than reformatting numbers.
 */
public inherited sharing class FormatUtils {
    /** Locale-grouped amount, e.g. 1234567.5 -> "1,234,567.5". Blank for null. */
    public static String formatAmount(Decimal amount) {
        return amount == null ? '' : amount.format();
    }

    /** ISO date string, e.g. "2026-07-02". Blank for null. */
    public static String formatDate(Date value) {
        return value == null ? '' : String.valueOf(value);
    }
}