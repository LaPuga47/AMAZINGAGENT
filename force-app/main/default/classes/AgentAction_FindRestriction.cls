/**
 * Agent Action: Find Restriction. Thin invocable wrapper — maps request/response
 * DTOs to RestrictionService. Contains NO SOQL and NO business logic. Gated by a
 * feature flag; every invocation is logged; errors return a safe message.
 */
public with sharing class AgentAction_FindRestriction {
  @TestVisible
  private static final String ACTION_NAME = 'AgentAction_FindRestriction';

  @TestVisible
  private static IRestrictionService service = new RestrictionService();

  @InvocableMethod(
    label='Find Restriction'
    description='Search fund Restrictions by name, related gift commitment, and/or country. Read-only.'
    category='OAF Employee Agent'
  )
  public static List<Response> findRestriction(List<Request> requests) {
    List<Response> responses = new List<Response>();
    for (Request request : requests) {
      responses.add(handle(request));
    }
    return responses;
  }

  private static Response handle(Request request) {
    Long startMs = System.currentTimeMillis();
    try {
      if (!FeatureFlag.isEnabled(ACTION_NAME)) {
        return toResponse(
          ResponseBuilder.error(
            'The Find Restriction action is currently disabled.'
          ),
          null
        );
      }

      Id giftCommitmentId = null;
      if (String.isNotBlank(request.giftCommitmentId)) {
        ValidationUtils.require(
          ValidationUtils.isValidId(request.giftCommitmentId),
          'The provided Gift Commitment Id is not a valid Salesforce Id.'
        );
        giftCommitmentId = (Id) request.giftCommitmentId;
      }

      Id opportunityId = null;
      if (String.isNotBlank(request.opportunityId)) {
        ValidationUtils.require(
          ValidationUtils.isValidId(request.opportunityId),
          'The provided Opportunity Id is not a valid Salesforce Id.'
        );
        opportunityId = (Id) request.opportunityId;
      }

      List<RestrictionSummary> results = service.findRestrictions(
        request.searchTerm,
        giftCommitmentId,
        opportunityId,
        request.country,
        request.maxResults
      );

      SearchResult envelope = results.isEmpty()
        ? ResponseBuilder.empty('No restrictions matched your search.')
        : ResponseBuilder.success(results.size());

      Logger.action(
        ACTION_NAME,
        envelope.message,
        System.currentTimeMillis() - startMs
      );
      return toResponse(envelope, results);
    } catch (AppException ae) {
      Logger.error(ACTION_NAME, ae.getMessage());
      return toResponse(ResponseBuilder.error(ae.getMessage()), null);
    } catch (Exception e) {
      Logger.error(ACTION_NAME, e.getMessage());
      return toResponse(
        ResponseBuilder.error(
          'Something went wrong while searching restrictions.'
        ),
        null
      );
    }
  }

  private static Response toResponse(
    SearchResult envelope,
    List<RestrictionSummary> results
  ) {
    Response response = new Response();
    response.success = envelope.success;
    response.message = envelope.message;
    response.count = envelope.count;
    response.restrictions = results == null
      ? new List<RestrictionSummary>()
      : results;
    List<AgentRecordResult> refs = new List<AgentRecordResult>();
    if (results != null) {
      for (RestrictionSummary s : results) {
        if (s.record != null) {
          refs.add(s.record);
        }
      }
    }
    response.records = refs;
    response.resultsText = buildResultsText(results);
    return response;
  }

  /** Human-readable summary the agent can surface directly. */
  private static String buildResultsText(List<RestrictionSummary> results) {
    if (results == null || results.isEmpty()) {
      return '';
    }
    List<String> lines = new List<String>();
    for (RestrictionSummary s : results) {
      String line = s.name;
      if (String.isNotBlank(s.giftCommitmentName)) {
        line += ' — Gift Commitment: ' + s.giftCommitmentName;
      }
      if (String.isNotBlank(s.country)) {
        line += ', Country: ' + s.country;
      }
      if (String.isNotBlank(s.staffOrOverhead)) {
        line += ', Staff/Overhead: ' + s.staffOrOverhead;
      }
      if (String.isNotBlank(s.timeRestricted)) {
        line += ', Time Restricted: ' + s.timeRestricted;
      }
      if (String.isNotBlank(s.theme)) {
        line += ', Theme: ' + s.theme;
      }
      if (s.timeAllocation != null) {
        line += ', Allocation: ' + FormatUtils.formatAmount(s.timeAllocation);
      }
      lines.add(line);
    }
    return SummaryText.sanitize(String.join(lines, '\n'));
  }

  public class Request {
    @InvocableVariable(
      label='Search Term'
      description='Full or partial restriction name.'
      required=false
    )
    public String searchTerm;
    @InvocableVariable(
      label='Gift Commitment Id'
      description='Restrict results to this Gift Commitment Id.'
      required=false
    )
    public String giftCommitmentId;
    @InvocableVariable(
      label='Opportunity Id'
      description='Restrict results to restrictions linked (via their Gift Commitment) to this Opportunity Id.'
      required=false
    )
    public String opportunityId;
    @InvocableVariable(
      label='Country'
      description='Restrict results to this restriction country.'
      required=false
    )
    public String country;
    @InvocableVariable(
      label='Max Results'
      description='Max records to return (default 10, max 50).'
      required=false
    )
    public Integer maxResults;
  }

  public class Response {
    @InvocableVariable(
      label='Success'
      description='Whether the search ran successfully.'
    )
    public Boolean success;
    @InvocableVariable(
      label='Message'
      description='Human-readable status message.'
    )
    public String message;
    @InvocableVariable(
      label='Count'
      description='Number of restrictions returned.'
    )
    public Integer count;
    @InvocableVariable(
      label='Results Text'
      description='Human-readable summary of the matching restrictions.'
    )
    public String resultsText;
    @InvocableVariable(
      label='Restrictions'
      description='Matching restrictions.'
    )
    public List<RestrictionSummary> restrictions;
    @InvocableVariable(
      label='Records'
      description='Clickable record cards for the matching records.'
    )
    public List<AgentRecordResult> records;
  }
}