/**
 * Reusable, prompt-agnostic search helpers: LIKE-term escaping and result-limit
 * clamping. Bind variables (not string concatenation) still carry the values
 * into SOQL; this only neutralizes LIKE wildcards and bounds page size.
 */
public inherited sharing class SearchUtils {
    private static final Integer DEFAULT_LIMIT = 10;
    private static final Integer MAX_LIMIT = 50;

    public static Integer clampLimit(Integer requested) {
        return clampLimit(requested, DEFAULT_LIMIT, MAX_LIMIT);
    }

    public static Integer clampLimit(Integer requested, Integer defaultLimit, Integer maxLimit) {
        if (requested == null || requested <= 0) {
            return defaultLimit;
        }
        return Math.min(requested, maxLimit);
    }

    /** Escapes LIKE special characters (\ % _) in a user-supplied term. */
    public static String escapeLike(String term) {
        if (String.isBlank(term)) {
            return '';
        }
        return term.trim().replace('\\', '\\\\').replace('%', '\\%').replace('_', '\\_');
    }

    /** Builds a "contains" LIKE pattern: "  Foo " -> "%Foo%". */
    public static String forContains(String term) {
        if (String.isBlank(term)) {
            return '%';
        }
        return '%' + escapeLike(term) + '%';
    }
}