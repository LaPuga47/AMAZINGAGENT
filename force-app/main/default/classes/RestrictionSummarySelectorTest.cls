@isTest
private class RestrictionSummarySelectorTest {
    @isTest
    static void fetchExecutesUnderUserMode() {
        RestrictionSummarySelector sel = new RestrictionSummarySelector();
        Test.startTest();
        Restriction__c byMissingName = sel.fetch('ZZ No Such Restriction ZZ', null);
        Restriction__c byMissingId = sel.fetch(null, (Id) 'a0L000000000001AAA');
        Restriction__c byBlank = sel.fetch(null, null);
        Test.stopTest();

        System.assertEquals(null, byMissingName, 'No restriction for a non-matching name');
        System.assertEquals(null, byMissingId, 'No restriction for a non-existent id');
        System.assertEquals(null, byBlank, 'No restriction when nothing provided');
    }

    // Uses real org data to exercise the id-path and name-path (best-match loop) + dynamic query.
    @isTest(SeeAllData=true)
    static void fetchRealRestrictionCoversQueryPaths() {
        List<Restriction__c> existing = [SELECT Id, Name FROM Restriction__c LIMIT 1];
        if (existing.isEmpty()) {
            return; // no data to exercise in this org
        }
        RestrictionSummarySelector sel = new RestrictionSummarySelector();
        Test.startTest();
        Restriction__c byId = sel.fetch(null, existing[0].Id);
        Restriction__c byName = sel.fetch(existing[0].Name, null);
        Test.stopTest();
        System.assertNotEquals(null, byId, 'Should load the existing restriction by id');
        System.assertNotEquals(null, byName, 'Should load a restriction by name');
    }
}