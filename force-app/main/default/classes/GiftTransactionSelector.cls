/**
 * All SOQL for GiftTransaction. Runs WITH USER_MODE (AccessLevel.USER_MODE) so FLS
 * and sharing are enforced for the running employee. No business logic, no DML.
 */
public with sharing class GiftTransactionSelector implements IGiftTransactionSelector {
    public List<GiftTransaction> search(
        String searchTerm,
        Id donorId,
        Id giftCommitmentId,
        Id campaignId,
        String status,
        Integer maxRecords
    ) {
        Integer recordLimit = SearchUtils.clampLimit(maxRecords);

        List<String> clauses = new List<String>();
        Map<String, Object> binds = new Map<String, Object>();

        if (String.isNotBlank(searchTerm)) {
            clauses.add('Name LIKE :term');
            binds.put('term', SearchUtils.forContains(searchTerm));
        }
        if (donorId != null) {
            clauses.add('DonorId = :donorId');
            binds.put('donorId', donorId);
        }
        if (giftCommitmentId != null) {
            clauses.add('GiftCommitmentId = :giftCommitmentId');
            binds.put('giftCommitmentId', giftCommitmentId);
        }
        if (campaignId != null) {
            clauses.add('CampaignId = :campaignId');
            binds.put('campaignId', campaignId);
        }
        if (String.isNotBlank(status)) {
            clauses.add('Status = :status');
            binds.put('status', status);
        }
        binds.put('recordLimit', recordLimit);

        String whereClause = clauses.isEmpty() ? '' : ' WHERE ' + String.join(clauses, ' AND ');
        String query =
            'SELECT Id, Name, Status, TransactionDate, OriginalAmount, CurrentAmount, PaymentMethod, ' +
            'GiftType, DonorId, Donor.Name, GiftCommitmentId, GiftCommitment.Name, CampaignId, Campaign.Name ' +
            'FROM GiftTransaction' + whereClause +
            ' ORDER BY TransactionDate DESC NULLS LAST, Name ASC LIMIT :recordLimit';

        return Database.queryWithBinds(query, binds, AccessLevel.USER_MODE);
    }
}