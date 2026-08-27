/**
 * AmaizeLink — builds clickable Salesforce record links for agent responses. URLs are
 * constructed server-side from the org's own domain (never hard-coded sandbox/production
 * hostnames, never guessed by the LLM), so a Relationship Manager can click a result in the
 * Agentforce window and open the underlying record.
 *
 * Lightning record URL shape: {orgDomain}/lightning/r/{ObjectApiName}/{RecordId}/view
 */
public with sharing class AmaizeLink {

    // Resolve the org domain once per transaction.
    private static String domainCache;

    private static String orgDomain() {
        if (domainCache == null) {
            // getOrgDomainUrl() returns the org's My Domain base URL (enhanced-domain safe).
            domainCache = URL.getOrgDomainUrl().toExternalForm();
        }
        return domainCache;
    }

    /** Absolute Lightning URL for a record, or null if the id is missing. */
    public static String recordUrl(String objectApiName, Id recordId) {
        if (recordId == null || String.isBlank(objectApiName)) { return null; }
        return orgDomain() + '/lightning/r/' + objectApiName + '/' + recordId + '/view';
    }

    /**
     * A Markdown link "[label](url)" to a record. Falls back to just the label when the id
     * is missing, and to a generic label when the label is blank — never emits a bare id.
     */
    public static String md(String label, String objectApiName, Id recordId) {
        String text = String.isBlank(label) ? '(record)' : label.trim();
        String url = recordUrl(objectApiName, recordId);
        return url == null ? text : '[' + text + '](' + url + ')';
    }
}
