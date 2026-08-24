/**
 * Reusable, domain-agnostic response envelope produced by ResponseBuilder.
 * Carries operation status/message/count; the typed record list lives on each
 * Agent Action's own Response so this stays reusable across every domain.
 */
public class SearchResult {
    public Boolean success;
    public String message;
    public Integer count;
}