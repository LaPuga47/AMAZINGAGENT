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
        // Treat a missing value as zero so we never print "null".
        if (value == null) {
            value = 0;
        }
        // Remember whether the number was negative, then work with its size.
        Boolean isNegative = value < 0;
        Decimal size = Math.abs(value);
        String text;

        if (size >= 1000000) {
            // Millions: show up to two decimals, then drop trailing zeros (1.10 -> 1.1, 2.00 -> 2).
            Decimal millions = (size / 1000000).setScale(2);
            text = '$' + trimZeros(millions) + 'M';
        } else if (size >= 1000) {
            // Thousands: round to a whole number of thousands (350000 -> 350K).
            Decimal thousands = (size / 1000).setScale(0, System.RoundingMode.HALF_UP);
            text = '$' + String.valueOf(thousands) + 'K';
        } else {
            // Small amounts: just show the whole number of dollars.
            text = '$' + String.valueOf(size.setScale(0, System.RoundingMode.HALF_UP));
        }
        // Put the minus sign in front of the dollar sign for negatives.
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