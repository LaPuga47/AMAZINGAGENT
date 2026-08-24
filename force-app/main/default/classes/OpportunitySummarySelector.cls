/**
 * Cross-object read layer for the Opportunity 360 summary. All SOQL runs
 * WITH USER_MODE (FLS + sharing enforced). No business logic, no DML. Gift
 * Transactions and Restrictions are matched through the Opportunity's linked
 * Gift Commitment(s).
 */
public with sharing class OpportunitySummarySelector implements IOpportunitySummarySelector {
    public OpportunitySummaryData fetch(String searchTerm, Id opportunityId) {
        OpportunitySummaryData data = new OpportunitySummaryData();
        data.opp = findOpportunity(searchTerm, opportunityId);
        if (data.opp == null) {
            return data;
        }

        data.commitments = [
            SELECT Id, Name, Status, ExpectedTotalCmtAmount, TotalPaidTransactionAmount, Remaining_Balance__c
            FROM GiftCommitment
            WHERE OpportunityId = :data.opp.Id
            WITH USER_MODE
        ];

        Set<Id> commitmentIds = new Map<Id, GiftCommitment>(data.commitments).keySet();
        // Safe with an empty set (returns no rows); keeps the query paths simple and covered.
        data.transactions = [
            SELECT Id, Name, Status, CurrentAmount, OriginalAmount, TransactionDate
            FROM GiftTransaction
            WHERE GiftCommitmentId IN :commitmentIds
            WITH USER_MODE
            ORDER BY TransactionDate DESC NULLS LAST
        ];
        String restrictionFields = 'Id, Name, Restriction_Country__c, Gift_Commitment__c, ' +
            String.join(RestrictionAllocation.yearlyFields(), ', ');
        data.restrictions = Database.queryWithBinds(
            'SELECT ' + restrictionFields + ' FROM Restriction__c WHERE Gift_Commitment__c IN :commitmentIds',
            new Map<String, Object>{ 'commitmentIds' => commitmentIds },
            AccessLevel.USER_MODE
        );
        return data;
    }

    private Opportunity findOpportunity(String searchTerm, Id opportunityId) {
        if (opportunityId != null) {
            List<Opportunity> byId = [
                SELECT Id, Name, StageName, Amount, Probability, CloseDate, CurrencyIsoCode,
                       Account.Name, Owner.Name, CampaignId, Campaign.Name
                FROM Opportunity
                WHERE Id = :opportunityId
                WITH USER_MODE
                LIMIT 1
            ];
            return byId.isEmpty() ? null : byId[0];
        }
        if (String.isBlank(searchTerm)) {
            return null;
        }
        String likeTerm = SearchUtils.forContains(searchTerm);
        List<Opportunity> matches = [
            SELECT Id, Name, StageName, Amount, Probability, CloseDate, CurrencyIsoCode,
                   Account.Name, Owner.Name, CampaignId, Campaign.Name
            FROM Opportunity
            WHERE Name LIKE :likeTerm
            WITH USER_MODE
            ORDER BY CloseDate DESC NULLS LAST
            LIMIT 10
        ];
        if (matches.isEmpty()) {
            return null;
        }
        Opportunity best = matches[0];
        Integer bestScore = -1;
        for (Opportunity o : matches) {
            Integer score = EntityMatcher.score(searchTerm, o.Name);
            if (score > bestScore) {
                bestScore = score;
                best = o;
            }
        }
        return best;
    }
}