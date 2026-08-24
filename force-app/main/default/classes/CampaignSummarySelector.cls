/**
 * Cross-object read layer for the Campaign Performance 360. All SOQL runs
 * WITH USER_MODE. Uses Salesforce-maintained Campaign rollup fields plus live
 * aggregates for open pipeline, gift transactions (by status), and members.
 * Executive-friendly: aggregates only, no per-record lists. No DML.
 */
public with sharing class CampaignSummarySelector implements ICampaignSummarySelector {
    public CampaignSummaryData fetch(String searchTerm, Id campaignId) {
        CampaignSummaryData data = new CampaignSummaryData();
        data.camp = findCampaign(searchTerm, campaignId);
        if (data.camp == null) {
            return data;
        }
        Id cid = data.camp.Id;

        AggregateResult openAgg = [
            SELECT SUM(Amount) total, COUNT(Id) cnt
            FROM Opportunity
            WHERE CampaignId = :cid AND IsClosed = false
            WITH USER_MODE
        ];
        data.openPipelineAmount = (Decimal) openAgg.get('total');
        data.openOpportunityCount = (Integer) openAgg.get('cnt');

        // Gift transactions attributed to the campaign directly (CampaignId) or via
        // a gift commitment linked to the campaign. Broken down by status.
        Set<Id> commitmentIds = new Map<Id, GiftCommitment>([
            SELECT Id FROM GiftCommitment WHERE CampaignId = :cid WITH USER_MODE
        ]).keySet();

        Integer total = 0;
        for (AggregateResult ar : [
            SELECT Status st, COUNT(Id) cnt, SUM(CurrentAmount) amt
            FROM GiftTransaction
            WHERE CampaignId = :cid OR GiftCommitmentId IN :commitmentIds
            WITH USER_MODE
            GROUP BY Status
        ]) {
            String st = (String) ar.get('st');
            if (String.isBlank(st)) {
                st = 'None';
            }
            Integer cnt = (Integer) ar.get('cnt');
            Decimal amt = (Decimal) ar.get('amt');
            data.giftCountByStatus.put(st, cnt);
            data.giftAmountByStatus.put(st, amt == null ? 0 : amt);
            total += cnt;
        }
        data.totalGiftTransactionCount = total;
        data.paidGiftTransactionCount = data.giftCountByStatus.containsKey('Paid') ? data.giftCountByStatus.get('Paid') : 0;
        data.giftReceivedAmount = data.giftAmountByStatus.containsKey('Paid') ? data.giftAmountByStatus.get('Paid') : 0;

        // Campaign members.
        data.memberCount = [SELECT COUNT() FROM CampaignMember WHERE CampaignId = :cid WITH USER_MODE];
        data.respondedMemberCount = [SELECT COUNT() FROM CampaignMember WHERE CampaignId = :cid AND HasResponded = true WITH USER_MODE];
        for (AggregateResult ar : [
            SELECT Status st, COUNT(Id) cnt
            FROM CampaignMember
            WHERE CampaignId = :cid
            WITH USER_MODE
            GROUP BY Status
        ]) {
            String st = (String) ar.get('st');
            data.memberStatusCounts.put(String.isBlank(st) ? 'None' : st, (Integer) ar.get('cnt'));
        }
        return data;
    }

    private Campaign findCampaign(String searchTerm, Id campaignId) {
        String fields =
            'Id, Name, Type, Status, IsActive, StartDate, EndDate, CurrencyIsoCode, Owner.Name, ' +
            'NumberOfOpportunities, NumberOfWonOpportunities, AmountAllOpportunities, ' +
            'AmountWonOpportunities, NumberOfContacts, NumberOfResponses, ' +
            'ActualCost, BudgetedCost, ExpectedRevenue';
        if (campaignId != null) {
            List<Campaign> byId = Database.queryWithBinds(
                'SELECT ' + fields + ' FROM Campaign WHERE Id = :campaignId LIMIT 1',
                new Map<String, Object>{ 'campaignId' => campaignId },
                AccessLevel.USER_MODE
            );
            return byId.isEmpty() ? null : byId[0];
        }
        if (String.isBlank(searchTerm)) {
            return null;
        }
        List<Campaign> matches = Database.queryWithBinds(
            'SELECT ' + fields + ' FROM Campaign WHERE Name LIKE :term ORDER BY StartDate DESC NULLS LAST LIMIT 10',
            new Map<String, Object>{ 'term' => SearchUtils.forContains(searchTerm) },
            AccessLevel.USER_MODE
        );
        if (matches.isEmpty()) {
            return null;
        }
        Campaign best = matches[0];
        Integer bestScore = -1;
        for (Campaign c : matches) {
            Integer score = EntityMatcher.score(searchTerm, c.Name);
            if (score > bestScore) {
                bestScore = score;
                best = c;
            }
        }
        return best;
    }
}