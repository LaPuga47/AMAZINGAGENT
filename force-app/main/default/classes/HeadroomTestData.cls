/**
 * HeadroomTestData — test data factory for the Budget-Line-first headroom analysis.
 *
 * Kept separate from AmaizeTestData so the existing demo tests are untouched. Builds a
 * single current Budget_Scenario__c and precise Budget_Line__c rows (with the seven
 * identifying dimensions), and — for the allocation cases — the full
 * Account -> GiftCommitment -> Restriction (+ Fund) -> Allocation chain the org uses.
 *
 * GiftCommitments are created WITHOUT an Opportunity so Allocation.Probability__c is
 * null; that keeps the "Classify Allocation Type by Probability" flow from firing, so
 * the Allocation_Type__c we set stands. No SeeAllData.
 */
@isTest
public class HeadroomTestData {

    public static final String FY = '2027';

    /** Insert the one current budget scenario for FY2027. */
    public static Budget_Scenario__c makeCurrentScenario() {
        Budget_Scenario__c s = new Budget_Scenario__c(
            Scenario_Type__c = 'Forecast Scenario',
            Effective_Date__c = Date.newInstance(2027, 1, 1),
            External_Key__c = 'HEADROOM-TEST-SCENARIO-2027',
            Is_Current_Scenario__c = true,
            Fiscal_Year__c = FY);
        insert s;
        return s;
    }

    /** Insert a Budget Line with all seven dimensions and funding figures; return it requeried. */
    public static Budget_Line__c makeLine(Id scenarioId, String country, String businessUnit,
            String subUnit, String department, String costType, String costCategory,
            Decimal budgetAmount, Decimal secured, Decimal likely, Decimal pipeline) {
        Budget_Line__c bl = new Budget_Line__c(
            Budget_Scenario__c = scenarioId,
            Country__c = country,
            BusinessUnit__c = businessUnit,
            Sub__c = subUnit,
            Department__c = department,
            Cost_Type__c = costType,
            Cost_Category__c = costCategory,
            Fiscal_Year__c = FY,
            Budget_Amount__c = budgetAmount,
            Secured_Funding__c = secured,
            Likely_Funding__c = likely,
            Pipeline_Funding__c = pipeline);
        insert bl;
        return requery(bl.Id);
    }

    /** Requery a Budget Line with every field the headroom code reads (incl. formula fields). */
    public static Budget_Line__c requery(Id budgetLineId) {
        return [
            SELECT Id, Name, Fiscal_Year__c, Country__c, BusinessUnit__c, Sub__c, Department__c,
                   Cost_Type__c, Cost_Category__c, Budget_Line_Unique_Key__c, CurrencyIsoCode,
                   Budget_Amount__c, Secured_Funding__c, Likely_Funding__c, Pipeline_Funding__c,
                   Forecast_Funding__c, Secured_Headroom__c, Forecast_Headroom__c,
                   Headroom_status__c, Matched__c
            FROM Budget_Line__c WHERE Id = :budgetLineId
        ];
    }

    /**
     * Create one Allocation through the full required chain. When budgetLineId is given
     * it is set as the DIRECT link; when null the allocation is left for the Match Key
     * path. The restriction dimensions drive Allocation_Match_Key__c.
     *
     * The org's "Classify Allocation Type by Probability" flow OWNS Allocation_Type__c
     * (Secured=100%, Likely=50-99%, Pipeline<50%), so we don't set it directly — we set
     * the linked grant's Probability to the value that yields desiredType, and let the
     * flow classify. This exercises the real classification rather than fighting it.
     */
    public static Allocation__c makeAllocation(String desiredType, Decimal funds, Id budgetLineId,
            String country, String businessUnit, String subUnit,
            String costType, String department, String costCategory) {
        Account donor = makeDonorAccount('Headroom Test Donor');

        // Grant with a controlled probability. Amount is left unset so the org's
        // "Opportunity After Save Flow" does not attempt to send a templated email.
        Opportunity opp = new Opportunity(
            Name = 'HR TEST OPP', AccountId = donor.Id,
            Country_Tag__c = country, Theme_Tag__c = 'Agroforestry/Tree',
            StageName = 'Negotiation', CloseDate = Date.newInstance(2027, 6, 1),
            Guardian__c = 'Test RM');
        insert opp;
        opp.Probability = probabilityFor(desiredType);
        update opp;

        GiftCommitment gc = new GiftCommitment(
            Name = 'HR TEST GC', DonorId = donor.Id, OpportunityId = opp.Id, Status = 'Active');
        insert gc;

        Restriction__c restr = new Restriction__c(
            Gift_Commitment__c = gc.Id,
            Restriction_Country__c = country,
            Business_Unit__c = businessUnit,
            Sub_Unit__c = subUnit,
            Cost_Type__c = costType,
            Department_Name__c = department,
            Cost_Category__c = costCategory,
            Line_Item__c = 'N/A',
            Incremental_Funds__c = 'No',
            Is_this_a_grant_to_a_sub_grantee__c = 'No');
        insert restr;

        Fund__c fund = new Fund__c(Name = FY);
        insert fund;

        Allocation__c a = new Allocation__c(
            Restriction__c = restr.Id,
            Fund__c = fund.Id,
            Funds_Allocated__c = funds);
        if (budgetLineId != null) {
            a.Budget_Line__c = budgetLineId;
        }
        insert a;
        return a;
    }

    /** Grant probability that makes the classifier flow produce the wanted Allocation Type. */
    private static Integer probabilityFor(String desiredType) {
        if (desiredType == 'Secured') { return 100; }
        if (desiredType == 'Likely') { return 75; }
        return 25; // Pipeline
    }

    /** One allocation to seed, all directly linked to a single Budget Line. */
    public class AllocSpec {
        public String desiredType;
        public Decimal funds;
        public AllocSpec(String desiredType, Decimal funds) {
            this.desiredType = desiredType;
            this.funds = funds;
        }
    }

    /**
     * Bulk-create several allocations DIRECTLY linked to one Budget Line, batching each
     * object's DML into a single statement so the DLRS trigger and org flows run in bulk
     * (avoids the per-record SOQL blowout of creating chains one at a time). Restriction
     * dimensions are all-N/A under the given country/business unit.
     */
    public static List<Allocation__c> makeAllocations(List<AllocSpec> specs, Id budgetLineId,
            String country, String businessUnit) {
        List<Contact> guardians = new List<Contact>();
        for (Integer i = 0; i < specs.size(); i++) {
            donorCounter++;
            guardians.add(new Contact(LastName = 'HR Bulk Donor ' + donorCounter + ' Guardian'));
        }
        insert guardians;

        Id rt = businessAccountRecordTypeId();
        List<Account> accounts = new List<Account>();
        for (Integer i = 0; i < specs.size(); i++) {
            Account a = new Account(
                Name = 'HR Bulk Donor ' + guardians[i].LastName, Type = 'Foundation',
                Account_Guardian__c = guardians[i].Id, BillingCity = 'Nairobi', BillingCountry = 'Kenya');
            if (rt != null) { a.RecordTypeId = rt; }
            accounts.add(a);
        }
        Database.DMLOptions dml = new Database.DMLOptions();
        dml.duplicateRuleHeader.allowSave = true;
        Database.insert(accounts, dml);

        List<Opportunity> opps = new List<Opportunity>();
        for (Integer i = 0; i < specs.size(); i++) {
            opps.add(new Opportunity(
                Name = 'HR Bulk OPP ' + i, AccountId = accounts[i].Id,
                Country_Tag__c = country, Theme_Tag__c = 'Agroforestry/Tree',
                StageName = 'Negotiation', CloseDate = Date.newInstance(2027, 6, 1),
                Guardian__c = 'Test RM'));
        }
        insert opps;
        for (Integer i = 0; i < specs.size(); i++) {
            opps[i].Probability = probabilityFor(specs[i].desiredType);
        }
        update opps;

        List<GiftCommitment> gcs = new List<GiftCommitment>();
        for (Integer i = 0; i < specs.size(); i++) {
            gcs.add(new GiftCommitment(
                Name = 'HR Bulk GC ' + i, DonorId = accounts[i].Id,
                OpportunityId = opps[i].Id, Status = 'Active'));
        }
        insert gcs;

        List<Restriction__c> restrs = new List<Restriction__c>();
        for (Integer i = 0; i < specs.size(); i++) {
            restrs.add(new Restriction__c(
                Gift_Commitment__c = gcs[i].Id,
                Restriction_Country__c = country,
                Business_Unit__c = businessUnit,
                Sub_Unit__c = 'N/A', Cost_Type__c = 'N/A', Department_Name__c = 'N/A',
                Cost_Category__c = 'N/A', Line_Item__c = 'N/A',
                Incremental_Funds__c = 'No', Is_this_a_grant_to_a_sub_grantee__c = 'No'));
        }
        insert restrs;

        List<Fund__c> funds = new List<Fund__c>();
        for (Integer i = 0; i < specs.size(); i++) {
            funds.add(new Fund__c(Name = FY));
        }
        insert funds;

        List<Allocation__c> allocs = new List<Allocation__c>();
        for (Integer i = 0; i < specs.size(); i++) {
            allocs.add(new Allocation__c(
                Restriction__c = restrs[i].Id, Fund__c = funds[i].Id,
                Funds_Allocated__c = specs[i].funds, Budget_Line__c = budgetLineId));
        }
        insert allocs;
        return allocs;
    }

    /**
     * One Opportunity allocated across SEVERAL Budget Lines (one allocation per line, same
     * type/amount), for testing that competing-grants sums a grant's exposure once by
     * Opportunity across the whole population.
     */
    public static void makeOppAllocations(String desiredType, List<Id> budgetLineIds, Decimal amountEach,
            String country, String businessUnit) {
        Account donor = makeDonorAccount('HR Multi Donor');
        Opportunity opp = new Opportunity(
            Name = 'HR MULTI OPP', AccountId = donor.Id, Country_Tag__c = country,
            Theme_Tag__c = 'Agroforestry/Tree', StageName = 'Negotiation',
            CloseDate = Date.newInstance(2027, 6, 1), Guardian__c = 'Test RM');
        insert opp;
        opp.Probability = probabilityFor(desiredType);
        update opp;
        GiftCommitment gc = new GiftCommitment(
            Name = 'HR MULTI GC', DonorId = donor.Id, OpportunityId = opp.Id, Status = 'Active');
        insert gc;
        Restriction__c restr = new Restriction__c(
            Gift_Commitment__c = gc.Id, Restriction_Country__c = country, Business_Unit__c = businessUnit,
            Sub_Unit__c = 'N/A', Cost_Type__c = 'N/A', Department_Name__c = 'N/A',
            Cost_Category__c = 'N/A', Line_Item__c = 'N/A',
            Incremental_Funds__c = 'No', Is_this_a_grant_to_a_sub_grantee__c = 'No');
        insert restr;
        Fund__c fund = new Fund__c(Name = FY);
        insert fund;
        List<Allocation__c> allocs = new List<Allocation__c>();
        for (Id blId : budgetLineIds) {
            allocs.add(new Allocation__c(
                Restriction__c = restr.Id, Fund__c = fund.Id,
                Funds_Allocated__c = amountEach, Budget_Line__c = blId));
        }
        insert allocs;
    }

    private static Integer donorCounter = 0;

    /** A donor Account that satisfies the org's Account validation rules. */
    public static Account makeDonorAccount(String name) {
        donorCounter++;
        String unique = name + ' ' + donorCounter;
        Contact guardian = new Contact(LastName = unique + ' Guardian');
        insert guardian;
        Account a = new Account(
            Name = unique, Type = 'Foundation',
            Account_Guardian__c = guardian.Id, BillingCity = 'Nairobi', BillingCountry = 'Kenya');
        Id rt = businessAccountRecordTypeId();
        if (rt != null) { a.RecordTypeId = rt; }
        // Bypass any Account duplicate rule so multiple test donors can be created in one run.
        Database.DMLOptions dml = new Database.DMLOptions();
        dml.duplicateRuleHeader.allowSave = true;
        Database.insert(a, dml);
        return a;
    }

    private static Id businessAccountRecordTypeId() {
        Map<String, Schema.RecordTypeInfo> byName =
            Account.SObjectType.getDescribe().getRecordTypeInfosByDeveloperName();
        Schema.RecordTypeInfo org = byName.get('Organization');
        if (org != null && org.isAvailable()) {
            return org.getRecordTypeId();
        }
        for (Schema.RecordTypeInfo rt : byName.values()) {
            if (rt.isAvailable() && !rt.isMaster()) {
                return rt.getRecordTypeId();
            }
        }
        return null;
    }
}
