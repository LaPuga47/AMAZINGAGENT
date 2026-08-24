/**
 * Agent Action: Get Gift Commitment Summary (Gift Commitment 360). Thin invocable
 * wrapper — maps request/response DTOs to GiftCommitmentSummaryService. Contains
 * NO SOQL and NO business logic. Returns a deterministic, grounded pledge 360.
 */
public with sharing class AgentAction_GetGiftCommitmentSummary {
  @TestVisible
  private static final String ACTION_NAME = 'AgentAction_GetGiftCommitmentSummary';

  @TestVisible
  private static IGiftCommitmentSummaryService service = new GiftCommitmentSummaryService();

  @InvocableMethod(
    label='Get Gift Commitment Summary'
    description='Return a complete 360 summary of a single Gift Commitment (pledge) — its donor, funding (expected / paid / received / outstanding), payment schedule, gift transactions, and restrictions. Use when the user asks to summarize or "tell me about" a specific gift commitment or pledge. Read-only.'
    category='OAF Employee Agent'
  )
  public static List<Response> getGiftCommitmentSummary(
    List<Request> requests
  ) {
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
          'The Get Gift Commitment Summary action is currently disabled.'
        );
      }

      Id commitmentId = null;
      if (String.isNotBlank(request.giftCommitmentId)) {
        ValidationUtils.require(
          ValidationUtils.isValidId(request.giftCommitmentId),
          'The provided Gift Commitment Id is not a valid Salesforce Id.'
        );
        commitmentId = (Id) request.giftCommitmentId;
      }
      if (commitmentId == null && String.isBlank(request.giftCommitmentName)) {
        return error('Please provide a gift commitment name or Id.');
      }

      GiftCommitmentSummaryResult summary = service.getSummary(
        request.giftCommitmentName,
        commitmentId
      );

      Response response = new Response();
      if (summary.found != true) {
        response.success = true;
        response.message = 'No matching gift commitment was found.';
        response.resultsText = '';
      } else {
        response.success = true;
        response.message = 'Gift commitment summary generated.';
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
        'Something went wrong while building the gift commitment summary.'
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
      label='Gift Commitment Name'
      description='Full or partial name of the gift commitment to summarize.'
      required=false
    )
    public String giftCommitmentName;
    @InvocableVariable(
      label='Gift Commitment Id'
      description='Gift Commitment record Id to summarize (used if provided).'
      required=false
    )
    public String giftCommitmentId;
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
      description='The full, grounded 360 summary of the gift commitment. Present this to the user.'
    )
    public String resultsText;
    @InvocableVariable(
      label='Record'
      description='Structured record reference for in-chat navigation (record Id, object, name, subtitle, summary).'
    )
    public AgentRecordResult record;
  }
}