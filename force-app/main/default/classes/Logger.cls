/**
 * Infrastructure logging for agent action invocations and errors. Writes to the
 * Log__c object (best-effort — a logging failure never breaks the caller) and
 * always echoes to the debug log. Correlation Id ties entries to one request.
 *
 * Note: Log__c inserts are infrastructure writes, exempt from the read-only
 * (no business DML) rule that applies to donor/financial data this phase.
 */
public with sharing class Logger {
    @TestVisible
    private static List<Log__c> buffer = new List<Log__c>();

    public static String correlationId() {
        return System.Request.getCurrent().getRequestId();
    }

    public static void info(String action, String message) {
        write('INFO', action, message, null);
    }

    public static void error(String action, String message) {
        write('ERROR', action, message, null);
    }

    /** Logs a completed action with its elapsed time in milliseconds. */
    public static void action(String action, String message, Long durationMs) {
        write('INFO', action, message, durationMs);
    }

    private static void write(String level, String action, String message, Long durationMs) {
        System.debug(level + ' [' + action + '] ' + message);
        Log__c entry = new Log__c(
            Correlation_Id__c = correlationId(),
            Level__c = level,
            Action__c = action,
            Message__c = message,
            Duration_Ms__c = durationMs
        );
        buffer.add(entry);
        try {
            insert entry;
        } catch (Exception e) {
            System.debug('Logger insert failed: ' + e.getMessage());
        }
    }
}