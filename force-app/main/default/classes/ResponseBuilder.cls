/**
 * Builds the uniform SearchResult envelope so every Agent Action reports status
 * consistently. success = the operation ran; empty = ran but no matches (still
 * success); error = the operation failed (message is user-safe).
 */
public inherited sharing class ResponseBuilder {
    public static SearchResult success(Integer count) {
        SearchResult result = new SearchResult();
        result.success = true;
        result.count = count;
        result.message = count + ' record(s) found.';
        return result;
    }

    public static SearchResult empty(String message) {
        SearchResult result = new SearchResult();
        result.success = true;
        result.count = 0;
        result.message = message;
        return result;
    }

    public static SearchResult error(String message) {
        SearchResult result = new SearchResult();
        result.success = false;
        result.count = 0;
        result.message = message;
        return result;
    }
}