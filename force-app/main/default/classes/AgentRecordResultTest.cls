@isTest
private class AgentRecordResultTest {
  @isTest
  static void constructsAndStringifiesId() {
    AgentRecordResult r = new AgentRecordResult(
      (Id) '006000000000001AAA',
      'Opportunity',
      'Test Grant'
    );
    System.assertEquals('006000000000001AAA', r.recordId, 'id stringified');
    System.assertEquals('Opportunity', r.objectApiName, 'object');
    System.assertEquals('Test Grant', r.recordName, 'name');
  }

  @isTest
  static void handlesNullId() {
    AgentRecordResult r = new AgentRecordResult(null, 'Account', 'X');
    System.assertEquals(null, r.recordId, 'null id -> null');
  }

  @isTest
  static void fluentSettersBlankToNull() {
    AgentRecordResult r = new AgentRecordResult(
        (Id) '001000000000001AAA',
        'Account',
        'Acme'
      )
      .withSubtitle('Foundation')
      .withSummary('');
    System.assertEquals('Foundation', r.subtitle, 'subtitle set');
    System.assertEquals(null, r.summary, 'blank summary -> null');
  }
}