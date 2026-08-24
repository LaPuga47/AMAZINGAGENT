/**
 * Selector contract for the Campaign Performance 360. Gathers the Campaign (with
 * its rollup fields), its related opportunities, and an open-pipeline aggregate
 * so the service can be unit-tested with a mock (no SOQL/DML in the service test).
 */
public interface ICampaignSummarySelector {
    CampaignSummaryData fetch(String searchTerm, Id campaignId);
}