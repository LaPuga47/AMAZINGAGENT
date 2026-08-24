/**
 * Reusable, prompt-agnostic input validation. Throws ValidationException with a
 * user-safe message when a requirement is not met.
 */
public inherited sharing class ValidationUtils {
    public static Boolean isBlank(String value) {
        return String.isBlank(value);
    }

    public static Boolean isValidId(String value) {
        if (String.isBlank(value)) {
            return false;
        }
        try {
            Id.valueOf(value);
            return true;
        } catch (Exception e) {
            return false;
        }
    }

    /** Throws ValidationException(message) when condition is false. */
    public static void require(Boolean condition, String message) {
        if (!condition) {
            throw new ValidationException(message);
        }
    }
}