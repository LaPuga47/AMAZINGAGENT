/**
 * AmaizeFormat — small shared helper for the A-maize-ing agent actions.
 * Turns raw currency numbers into short, human-friendly strings like "$1.1M"
 * or "$350K" so the agent's spoken responses read the way the brief shows them.
 */
public with sharing class AmaizeFormat {

    /**
     * Format a currency amount the way a finance colleague would say it out loud:
     *   1100000  -> "$1.1M"      350000 -> "$350K"      -150000 -> "-$150K"
     *   2000000  -> "$2M"        80000  -> "$80K"        0       -> "$0"
     */
    public static String money(Decimal value) {
        return money(value, null);
    }

    // Widen the gap before a trailing follow-up question to TWO blank lines, so the answer reads as
    // complete before the agent asks what to do next. Only the final follow-up line (a single line
    // ending in "?") is affected; section spacing and record links are untouched. NOTE: the
    // Agentforce model/renderer collapses consecutive blank lines (and whitespace-only paragraphs)
    // to a single paragraph break, so the emitted two blank lines may render as one gap — that is a
    // platform limitation; a larger visible gap is not achievable without exposing markup.
    private static final String GAP = '\n\n\n';
    public static String spaceFollowUp(String summary) {
        if (String.isBlank(summary)) { return summary; }
        Matcher m = Pattern.compile('(?s)^(.*\\S)\\n{2,}([^\\n]*\\?)\\s*$').matcher(summary);
        return m.matches() ? m.group(1) + GAP + m.group(2).trim() : summary;
    }

    /**
     * Format a currency amount, preserving the record's currency. USD (or a blank
     * ISO code) renders with a "$" the way the brief shows it; any other currency is
     * prefixed with its ISO code so figures are never silently shown as dollars:
     *   money(1200000, 'KES') -> "KES 1.2M"      money(-150000, 'EUR') -> "-EUR 150K"
     */
    public static String money(Decimal value, String isoCode) {
        // Treat a missing value as zero so we never print "null".
        if (value == null) {
            value = 0;
        }
        // Remember whether the number was negative, then work with its size.
        Boolean isNegative = value < 0;
        Decimal size = Math.abs(value);
        String amountText;

        if (size >= 1000000) {
            // Millions: show up to two decimals, then drop trailing zeros (1.10 -> 1.1, 2.00 -> 2).
            amountText = trimZeros((size / 1000000).setScale(2)) + 'M';
        } else if (size >= 1000) {
            // Thousands: round to a whole number of thousands (350000 -> 350K).
            amountText = String.valueOf((size / 1000).setScale(0, System.RoundingMode.HALF_UP)) + 'K';
        } else {
            // Small amounts: just show the whole number.
            amountText = String.valueOf(size.setScale(0, System.RoundingMode.HALF_UP));
        }

        // USD / blank -> "$"; any other currency -> "ISO " prefix so it's unmistakable.
        String symbol = (String.isBlank(isoCode) || isoCode.equalsIgnoreCase('USD'))
            ? '$'
            : isoCode.trim().toUpperCase() + ' ';
        String text = symbol + amountText;

        // Put the minus sign in front of the amount for negatives.
        return isNegative ? '-' + text : text;
    }

    /**
     * Remove trailing zeros after a decimal point: "1.10" -> "1.1", "2.00" -> "2".
     * Keeps millions strings tidy.
     */
    private static String trimZeros(Decimal d) {
        String s = String.valueOf(d);
        if (s.contains('.')) {
            // Strip trailing zeros, then a dangling decimal point if one is left.
            s = s.replaceAll('0+$', '');
            s = s.replaceAll('\\.$', '');
        }
        return s;
    }
}