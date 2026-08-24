@isTest
private class ResponseBuilderTest {
    @isTest
    static void successEnvelope() {
        SearchResult r = ResponseBuilder.success(3);
        System.assertEquals(true, r.success);
        System.assertEquals(3, r.count);
        System.assert(r.message.contains('3'), 'Message should mention the count');
    }

    @isTest
    static void emptyEnvelope() {
        SearchResult r = ResponseBuilder.empty('nothing here');
        System.assertEquals(true, r.success, 'Empty is still a successful operation');
        System.assertEquals(0, r.count);
        System.assertEquals('nothing here', r.message);
    }

    @isTest
    static void errorEnvelope() {
        SearchResult r = ResponseBuilder.error('it broke');
        System.assertEquals(false, r.success);
        System.assertEquals(0, r.count);
        System.assertEquals('it broke', r.message);
    }
}