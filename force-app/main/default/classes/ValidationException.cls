/**
 * Thrown when caller-supplied input fails validation (blank required value,
 * malformed Id, out-of-range argument). Its message is safe to surface to the
 * agent user.
 */
public class ValidationException extends AppException {}