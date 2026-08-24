/**
 * Agent Action: Get Restriction Summary (Restriction 360). Thin invocable wrapper
 * — maps request/response DTOs to RestrictionSummaryService. Contains NO SOQL and
 * NO business logic. Returns a deterministic, grounded restriction 360.
 */
public with sharing class AgentAction_GetRestrictionSummary {
  @TestVisible
  private static final String ACTION_NAME = 'AgentAction_GetRestrictionSummary';

  @TestVisible
  private static IRestrictionSummaryService service = new RestrictionSummaryService();

  @InvocableMethod(
    label='Get Restriction Summary'
    description='Return a complete 360 summary of a single fund Restriction — its purpose (country, theme, staff/overhead, time restriction, sub-grantee), parent gift commitment/donor, and total allocated funds with a per-year breakdown. Use when the user asks to summarize or "tell me about" a specific restriction. Read-only.'
    category='OAF Employee Agent'
  )
  public static List<Response> getRestrictionSummary(List<Request> requests) {
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
        return error(
          'The Get Restriction Summary action is currently disabled.'
        );
      }

      Id restrictionId = null;
      if (String.isNotBlank(request.restrictionId)) {
        ValidationUtils.require(
          ValidationUtils.isValidId(request.restrictionId),
          'The provided Restriction Id is not a valid Salesforce Id.'
        );
        restrictionId = (Id) request.restrictionId;
      }
      if (restrictionId == null && String.isBlank(request.restrictionName)) {
        return error('Please provide a restriction name or Id.');
      }

      RestrictionSummaryResult summary = service.getSummary(
        request.restrictionName,
        restrictionId
      );

      Response response = new Response();
      if (summary.found != true) {
        response.success = true;
        response.message = 'No matching restriction was found.';
        response.resultsText = '';
      } else {
        response.success = true;
        response.message = 'Restriction summary generated.';
        response.resultsText = summary.resultsText;
        response.record = summary.record;
      }
      Logger.action(
        ACTION_NAME,
        response.message,
        System.currentTimeMillis() - startMs
      );
      return response;
    } catch (AppException ae) {
      Logger.error(ACTION_NAME, ae.getMessage());
      return error(ae.getMessage());
    } catch (Exception e) {
      Logger.error(ACTION_NAME, e.getMessage());
      return error(
        'Something went wrong while building the restriction summary.'
      );
    }
  }

  private static Response error(String message) {
    Response response = new Response();
    response.success = false;
    response.message = message;
    response.resultsText = '';
    return response;
  }

  public class Request {
    @InvocableVariable(
      label='Restriction Name'
      description='Full or partial name of the restriction to summarize.'
      required=false
    )
    public String restrictionName;
    @InvocableVariable(
      label='Restriction Id'
      description='Restriction record Id to summarize (used if provided).'
      required=false
    )
    public String restrictionId;
  }

  public class Response {
    @InvocableVariable(
      label='Success'
      description='Whether the summary was generated successfully.'
    )
    public Boolean success;
    @InvocableVariable(
      label='Message'
      description='Human-readable status message.'
    )
    public String message;
    @InvocableVariable(
      label='Results Text'
      description='The full, grounded 360 summary of the restriction. Present this to the user.'
    )
    public String resultsText;
    @InvocableVariable(
      label='Record'
      description='Structured record reference for in-chat navigation (record Id, object, name, subtitle, summary).'
    )
    public AgentRecordResult record;
  }
}