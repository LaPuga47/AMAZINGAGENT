/**
 * Base application exception. Domain/service/action code throws subclasses of
 * this so the Agent Action layer can translate them into safe, user-facing
 * messages. Never leak raw stack traces to the agent/LLM.
 */
public virtual class AppException extends Exception {}