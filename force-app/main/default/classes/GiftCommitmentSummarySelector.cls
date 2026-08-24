/**
 * Cross-object read layer for the Gift Commitment 360. All SOQL runs
 * WITH USER_MODE. Transactions are matched by GiftCommitmentId; restrictions by
 * Gift_Commitment__c. No business logic, no DML.
 */
public with sharing class GiftCommitmentSummarySelector implements IGiftCommitmentSummarySelector {
    public GiftCommitmentSummaryData fetch(String searchTerm, Id commitmentId) {
        GiftCommitmentSummaryData data = new GiftCommitmentSummaryData();
        data.commitment = findCommitment(searchTerm, commitmentId);
        if (data.commitment == null) {
            return data;
        }
        Id cid = data.commitment.Id;

        data.transactions = [
            SELECT Id, Name, Status, CurrentAmount, TransactionDate
            FROM GiftTransaction
            WHERE GiftCommitmentId = :cid
            WITH USER_MODE
            ORDER BY TransactionDate DESC NULLS LAST
            LIMIT 2000
        ];
        String restrictionFields = 'Id, Name, Restriction_Country__c, Gift_Commitment__c, ' +
            String.join(RestrictionAllocation.yearlyFields(), ', ');
        data.restrictions = Database.queryWithBinds(
            'SELECT ' + restrictionFields + ' FROM Restriction__c WHERE Gift_Commitment__c = :cid',
            new Map<String, Object>{ 'cid' => cid },
            AccessLevel.USER_MODE
        );
        return data;
    }

    private GiftCommitment findCommitment(String searchTerm, Id commitmentId) {
        if (commitmentId != null) {
            List<GiftCommitment> byId = [
                SELECT Id, Name, Status, DonorId, Donor.Name, ExpectedTotalCmtAmount, TotalPaidTransactionAmount,
                       Remaining_Balance__c, EffectiveStartDate, ExpectedEndDate, NextTransactionDate,
                       NextTransactionAmount, RecurrenceType, ScheduleType, CurrencyIsoCode,
                       OpportunityId, Opportunity.Name, CampaignId, Campaign.Name
                FROM GiftCommitment
                WHERE Id = :commitmentId
                WITH USER_MODE
                LIMIT 1
            ];
            return byId.isEmpty() ? null : byId[0];
        }
        if (String.isBlank(searchTerm)) {
            return null;
        }
        String likeTerm = SearchUtils.forContains(searchTerm);
        List<GiftCommitment> matches = [
            SELECT Id, Name, Status, DonorId, Donor.Name, ExpectedTotalCmtAmount, TotalPaidTransactionAmount,
                   Remaining_Balance__c, EffectiveStartDate, ExpectedEndDate, NextTransactionDate,
                   NextTransactionAmount, RecurrenceType, ScheduleType, CurrencyIsoCode,
                   OpportunityId, Opportunity.Name, CampaignId, Campaign.Name
            FROM GiftCommitment
            WHERE Name LIKE :likeTerm
            WITH USER_MODE
            ORDER BY EffectiveStartDate DESC NULLS LAST
            LIMIT 10
        ];
        if (matches.isEmpty()) {
            return null;
        }
        GiftCommitment best = matches[0];
        Integer bestScore = -1;
        for (GiftCommitment gc : matches) {
            Integer score = EntityMatcher.score(searchTerm, gc.Name);
            if (score > bestScore) {
                bestScore = score;
                best = gc;
            }
        }
        return best;
    }
}