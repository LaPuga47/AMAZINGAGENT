@isTest
private class CampaignSummarySelectorTest {
    @isTest
    static void fetchExecutesUnderUserMode() {
        CampaignSummarySelector sel = new CampaignSummarySelector();
        Test.startTest();
        CampaignSummaryData byMissingName = sel.fetch('ZZ No Such Campaign ZZ', null);
        CampaignSummaryData byMissingId = sel.fetch(null, (Id) '701000000000001AAA');
        CampaignSummaryData byBlank = sel.fetch(null, null);
        Test.stopTest();

        System.assertNotEquals(null, byMissingName, 'Returns a data container');
        System.assertEquals(null, byMissingName.camp, 'No campaign for a non-matching name');
        System.assertEquals(null, byBlank.camp, 'No campaign when nothing provided');
        System.assertNotEquals(null, byMissingId, 'Returns a data container for id path');
    }

    // Uses real org data to exercise the full fetch (campaign + related queries + aggregate).
    @isTest(SeeAllData=true)
    static void fetchRealCampaignCoversRelatedQueries() {
        List<Campaign> existing = [SELECT Id, Name FROM Campaign LIMIT 1];
        if (existing.isEmpty()) {
            return; // no data to exercise in this org
        }
        CampaignSummarySelector sel = new CampaignSummarySelector();
        Test.startTest();
        CampaignSummaryData byId = sel.fetch(null, existing[0].Id);
        // Name path also exercises the name-search + best-match ranking loop.
        CampaignSummaryData byName = sel.fetch(existing[0].Name, null);
        Test.stopTest();
        System.assertNotEquals(null, byId.camp, 'Should load the existing campaign by id');
        System.assertNotEquals(null, byId.giftCountByStatus, 'Gift status breakdown map should be initialized');
        System.assertNotEquals(null, byId.memberStatusCounts, 'Member status breakdown map should be initialized');
        System.assertNotEquals(null, byName.camp, 'Should load a campaign by name');
    }
}