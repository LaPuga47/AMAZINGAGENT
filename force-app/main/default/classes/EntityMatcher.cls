/**
 * Reusable, prompt-agnostic relevance scoring for matching a user-supplied term
 * to a candidate string. Used to rank/disambiguate search results. Higher is a
 * better match: 100 exact, 75 starts-with, 50 contains, 0 none (case-insensitive).
 */
public inherited sharing class EntityMatcher {
    public static Integer score(String term, String candidate) {
        if (String.isBlank(term) || String.isBlank(candidate)) {
            return 0;
        }
        String t = term.trim().toLowerCase();
        String c = candidate.trim().toLowerCase();
        if (c == t) {
            return 100;
        }
        if (c.startsWith(t)) {
            return 75;
        }
        if (c.contains(t)) {
            return 50;
        }
        return 0;
    }
}