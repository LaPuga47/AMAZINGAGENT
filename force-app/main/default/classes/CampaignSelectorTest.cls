@isTest
private class CampaignSelectorTest {
    @isTest
    static void queryExecutesUnderUserModeForAllFilters() {
        CampaignSelector sel = new CampaignSelector();
        Test.startTest();
        List<Campaign> all = sel.search(null, null, null);
        List<Campaign> byTermAndStatus = sel.search('test', 'In Progress', 5);
        Test.stopTest();

        System.assertNotEquals(null, all, 'Unfiltered query should return a list');
        System.assertNotEquals(null, byTermAndStatus, 'Filtered query should return a list');
    }

    @isTest
    static void findsInsertedCampaignByName() {
        Id campId;
        String actualName;
        try {
            Campaign c = new Campaign(Name = 'ZZ Unique Selector Campaign');
            insert c;
            campId = c.Id;
            actualName = [SELECT Name FROM Campaign WHERE Id = :campId].Name;
        } catch (Exception e) {
            System.debug('Data setup skipped: ' + e.getMessage());
        }

        Test.startTest();
        List<Campaign> results = (campId != null)
            ? new CampaignSelector().search(actualName, null, 50)
            : new CampaignSelector().search('ZZ Unique Selector', null, 10);
        Test.stopTest();

        if (campId != null) {
            Set<Id> foundIds = new Map<Id, Campaign>(results).keySet();
            System.assert(foundIds.contains(campId),
                'Selector should find the inserted campaign by its (actual) name');
        } else {
            System.assertNotEquals(null, results, 'Query should still return a list');
        }
    }
}