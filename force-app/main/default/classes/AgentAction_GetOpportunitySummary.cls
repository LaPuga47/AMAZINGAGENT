/**
 * Agent Action: Get Opportunity Summary. Thin invocable wrapper — maps request/
 * response DTOs to OpportunitySummaryService. Contains NO SOQL and NO business
 * logic. Returns a deterministic, grounded 360 summary of one Opportunity.
 */
public with sharing class AgentAction_GetOpportunitySummary {
  @TestVisible
  private static final String ACTION_NAME = 'AgentAction_GetOpportunitySummary';

  @TestVisible
  private static IOpportunitySummaryService service = new OpportunitySummaryService();

  @InvocableMethod(
    label='Get Opportunity Summary'
    description='Return a complete 360 summary of a single Opportunity — its details, linked gift commitment, gift transactions (received vs. outstanding), and restrictions. Use when the user asks to summarize or "tell me about" a specific opportunity. Read-only.'
    category='OAF Employee Agent'
  )
  public static List<Response> getOpportunitySummary(List<Request> requests) {
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
          'The Get Opportunity Summary action is currently disabled.'
        );
      }

      Id opportunityId = null;
      if (String.isNotBlank(request.opportunityId)) {
        ValidationUtils.require(
          ValidationUtils.isValidId(request.opportunityId),
          'The provided Opportunity Id is not a valid Salesforce Id.'
        );
        opportunityId = (Id) request.opportunityId;
      }
      if (opportunityId == null && String.isBlank(request.opportunityName)) {
        return error('Please provide an opportunity name or Id.');
      }

      OpportunitySummaryResult summary = service.getSummary(
        request.opportunityName,
        opportunityId
      );

      Response response = new Response();
      if (summary.found != true) {
        response.success = true;
        response.message = 'No matching opportunity was found.';
        response.resultsText = '';
      } else {
        response.success = true;
        response.message = 'Opportunity summary generated.';
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
        'Something went wrong while building the opportunity summary.'
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
      label='Opportunity Name'
      description='Full or partial name of the opportunity to summarize.'
      required=false
    )
    public String opportunityName;
    @InvocableVariable(
      label='Opportunity Id'
      description='Opportunity record Id to summarize (used if provided).'
      required=false
    )
    public String opportunityId;
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
      description='The full, grounded 360 summary of the opportunity. Present this to the user.'
    )
    public String resultsText;
    @InvocableVariable(
      label='Record'
      description='Structured record reference for in-chat navigation (record Id, object, name, subtitle, summary).'
    )
    public AgentRecordResult record;
  }
}