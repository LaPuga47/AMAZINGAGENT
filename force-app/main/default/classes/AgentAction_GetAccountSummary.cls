/**
 * Agent Action: Get Account Summary (Account 360). Thin invocable wrapper — maps
 * request/response DTOs to AccountSummaryService. Contains NO SOQL and NO business
 * logic. Returns a deterministic, grounded 360 summary of one Account/donor.
 */
public with sharing class AgentAction_GetAccountSummary {
  @TestVisible
  private static final String ACTION_NAME = 'AgentAction_GetAccountSummary';

  @TestVisible
  private static IAccountSummaryService service = new AccountSummaryService();

  @InvocableMethod(
    label='Get Account Summary'
    description='Return a complete 360 summary of a single Account/donor — its details, key contacts, giving summary (committed vs. received vs. outstanding), and related opportunities. Use when the user asks to summarize or "tell me about" a specific account or donor. Read-only.'
    category='OAF Employee Agent'
  )
  public static List<Response> getAccountSummary(List<Request> requests) {
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
        return error('The Get Account Summary action is currently disabled.');
      }

      Id accountId = null;
      if (String.isNotBlank(request.accountId)) {
        ValidationUtils.require(
          ValidationUtils.isValidId(request.accountId),
          'The provided Account Id is not a valid Salesforce Id.'
        );
        accountId = (Id) request.accountId;
      }
      if (accountId == null && String.isBlank(request.accountName)) {
        return error('Please provide an account name or Id.');
      }

      AccountSummaryResult summary = service.getSummary(
        request.accountName,
        accountId
      );

      Response response = new Response();
      if (summary.found != true) {
        response.success = true;
        response.message = 'No matching account was found.';
        response.resultsText = '';
      } else {
        response.success = true;
        response.message = 'Account summary generated.';
        response.resultsText = summary.resultsText;
        response.record = summary.record;
        response.records = summary.records;
        response.accountCategory = summary.accountCategory;
        response.recordTypeName = summary.recordTypeName;
        response.recordTypeDeveloperName = summary.recordTypeDeveloperName;
        response.isPersonAccount = summary.isPersonAccount;
        response.accountType = summary.accountType;
        response.donorType = summary.donorType;
        response.donorStatus = summary.donorStatus;
        response.accountGuardian = summary.accountGuardian;
        response.ownerName = summary.ownerName;
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
      return error('Something went wrong while building the account summary.');
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
      label='Account Name'
      description='Full or partial name of the account/donor to summarize.'
      required=false
    )
    public String accountName;
    @InvocableVariable(
      label='Account Id'
      description='Account record Id to summarize (used if provided).'
      required=false
    )
    public String accountId;
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
      description='The full, grounded 360 summary of the account. Present this to the user.'
    )
    public String resultsText;
    @InvocableVariable(
      label='Record'
      description='Structured record reference for in-chat navigation (record Id, object, name, subtitle, summary).'
    )
    public AgentRecordResult record;
    @InvocableVariable(
      label='Records'
      description='Clickable cards for the related people (contacts and affiliations), or affiliated organizations for a person account.'
    )
    public List<AgentRecordResult> records;
    @InvocableVariable(
      label='Account Category'
      description='Person Account, Organization Account, Household Account, or Other Account.'
    )
    public String accountCategory;
    @InvocableVariable(
      label='Record Type Name'
      description='Account Record Type label.'
    )
    public String recordTypeName;
    @InvocableVariable(
      label='Record Type Developer Name'
      description='Account Record Type developer name.'
    )
    public String recordTypeDeveloperName;
    @InvocableVariable(
      label='Is Person Account'
      description='Whether the account is a Person Account.'
    )
    public Boolean isPersonAccount;
    @InvocableVariable(
      label='Account Type'
      description='Account Type picklist value.'
    )
    public String accountType;
    @InvocableVariable(label='Donor Type' description='Donor Type.')
    public String donorType;
    @InvocableVariable(label='Donor Status' description='Donor Status.')
    public String donorStatus;
    @InvocableVariable(
      label='Account Guardian'
      description='Account Guardian name.'
    )
    public String accountGuardian;
    @InvocableVariable(label='Owner Name' description='Account owner name.')
    public String ownerName;
  }
}