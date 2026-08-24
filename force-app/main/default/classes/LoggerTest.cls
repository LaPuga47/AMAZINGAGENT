@isTest
private class LoggerTest {
    @isTest
    static void writesEntriesForEachLevel() {
        Test.startTest();
        Logger.info('UnitTest', 'an info message');
        Logger.error('UnitTest', 'an error message');
        Logger.action('UnitTest', 'a completed action', 12);
        Test.stopTest();

        // Assert on the deterministic in-memory seam. Persistence to Log__c is
        // best-effort infrastructure and is intentionally not asserted here (a
        // unit test must not depend on org schema/DML behavior).
        System.assertEquals(3, Logger.buffer.size(), 'Three entries should be captured');
        System.assertEquals('INFO', Logger.buffer[0].Level__c);
        System.assertEquals('ERROR', Logger.buffer[1].Level__c);
        System.assertEquals('UnitTest', Logger.buffer[2].Action__c);
        System.assertEquals(12, Logger.buffer[2].Duration_Ms__c);
    }

    @isTest
    static void correlationIdIsPopulated() {
        System.assertNotEquals(null, Logger.correlationId(), 'Correlation Id should not be null');
    }
}