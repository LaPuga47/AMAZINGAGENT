/**
 * Agent Action: Get Campaign Summary (Campaign Performance 360). Thin invocable
 * wrapper — maps request/response DTOs to CampaignSummaryService. Contains NO
 * SOQL and NO business logic. Returns a deterministic, grounded performance 360.
 */
public with sharing class AgentAction_GetCampaignSummary {
  @TestVisible
  private static final String ACTION_NAME = 'AgentAction_GetCampaignSummary';

  @TestVisible
  private static ICampaignSummaryService service = new CampaignSummaryService();

  @InvocableMethod(
    label='Get Campaign Summary'
    description='Return a complete performance 360 of a single Campaign — its details, opportunity rollups (all/won amounts, counts), open pipeline, budget/ROI, and related opportunities. Use when the user asks to summarize or "tell me about" a specific campaign or its performance. Read-only.'
    category='OAF Employee Agent'
  )
  public static List<Response> getCampaignSummary(List<Request> requests) {
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
        return error('The Get Campaign Summary action is currently disabled.');
      }

      Id campaignId = null;
      if (String.isNotBlank(request.campaignId)) {
        ValidationUtils.require(
          ValidationUtils.isValidId(request.campaignId),
          'The provided Campaign Id is not a valid Salesforce Id.'
        );
        campaignId = (Id) request.campaignId;
      }
      if (campaignId == null && String.isBlank(request.campaignName)) {
        return error('Please provide a campaign name or Id.');
      }

      CampaignSummaryResult summary = service.getSummary(
        request.campaignName,
        campaignId
      );

      Response response = new Response();
      if (summary.found != true) {
        response.success = true;
        response.message = 'No matching campaign was found.';
        response.resultsText = '';
      } else {
        response.success = true;
        response.message = 'Campaign summary generated.';
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
      return error('Something went wrong while building the campaign summary.');
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
      label='Campaign Name'
      description='Full or partial name of the campaign to summarize.'
      required=false
    )
    public String campaignName;
    @InvocableVariable(
      label='Campaign Id'
      description='Campaign record Id to summarize (used if provided).'
      required=false
    )
    public String campaignId;
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
      description='The full, grounded performance 360 of the campaign. Present this to the user.'
    )
    public String resultsText;
    @InvocableVariable(
      label='Record'
      description='Structured record reference for in-chat navigation (record Id, object, name, subtitle, summary).'
    )
    public AgentRecordResult record;
  }
}