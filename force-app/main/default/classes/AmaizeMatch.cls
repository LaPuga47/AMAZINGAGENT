/**
 * AmaizeMatch — shared helper for matching a grant (Opportunity) by the loose,
 * natural-language name an RM types.
 *
 * In plain terms: an RM might say "Greenfield Kenya Core Program 2027" when the real
 * record is "Greenfield – Kenya Core Program 2027" (note the en-dash). A plain
 * substring search misses that. Instead we break what the RM typed into words and
 * keep any grant whose name contains all of those words — robust to punctuation,
 * extra spaces, and word order.
 */
public with sharing class AmaizeMatch {

    // Common little words we ignore when matching, so they don't force or break a match.
    private static final Set<String> STOP_WORDS = new Set<String>{
        'the', 'a', 'an', 'for', 'of', 'to', 'and', 'opportunity', 'grant', 'program'
    };

    /**
     * Return every grant whose name contains all the significant words from the
     * user's input. If the input is blank, returns an empty list.
     */
    public static List<Opportunity> tokenMatch(String userInput, List<Opportunity> opps) {
        List<Opportunity> hits = new List<Opportunity>();
        if (String.isBlank(userInput)) {
            return hits;
        }

        // Break the input into lowercase words, dropping punctuation and stop-words.
        List<String> tokens = significantTokens(userInput);
        if (tokens.isEmpty()) {
            return hits;
        }

        for (Opportunity o : opps) {
            if (o.Name == null) continue;
            String lname = o.Name.toLowerCase();
            // Keep this grant only if EVERY significant token appears in its name.
            Boolean allPresent = true;
            for (String t : tokens) {
                if (!lname.contains(t)) {
                    allPresent = false;
                    break;
                }
            }
            if (allPresent) {
                hits.add(o);
            }
        }
        return hits;
    }

    /**
     * Split text into lowercase word tokens, removing punctuation and stop-words.
     * "Greenfield – Kenya Core Program 2027" -> [greenfield, kenya, core, 2027]
     *
     * Public so callers that match names in SOQL (e.g. a LIKE per token) can reuse the
     * exact same tokenisation. The returned tokens are ALPHANUMERIC ONLY (all punctuation
     * is stripped), so they are safe to embed directly in a SOQL LIKE clause.
     */
    public static List<String> significantTokens(String text) {
        // Replace anything that isn't a letter or digit with a space, then split.
        String cleaned = text.toLowerCase().replaceAll('[^a-z0-9]', ' ');
        List<String> tokens = new List<String>();
        for (String part : cleaned.split('\\s+')) {
            if (String.isBlank(part)) continue;
            if (STOP_WORDS.contains(part)) continue;
            tokens.add(part);
        }
        return tokens;
    }
}