@isTest
private class SecurityGuardTest {
    @isTest
    static void readableObjectPasses() {
        System.assertEquals(true, SecurityGuard.isReadable(Opportunity.SObjectType),
            'Opportunity should be readable by the test user');
        SecurityGuard.assertReadable(Opportunity.SObjectType); // should not throw
    }

    @isTest
    static void stripReadReturnsRecords() {
        List<SObject> input = new List<SObject>{ new Opportunity(Name = 'x') };
        List<SObject> stripped = SecurityGuard.stripRead(input);
        System.assertEquals(1, stripped.size(), 'Accessible records should be returned');
    }
}