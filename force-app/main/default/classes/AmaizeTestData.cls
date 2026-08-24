/**
 * AmaizeTestData — shared test data factory for the A-maize-ing test classes.
 *
 * Creates the same fictional grants and headroom rows the demo uses, so every
 * test runs against realistic, predictable data without relying on org data
 * (no SeeAllData). Each test class calls makeAll() from its @TestSetup.
 */
@isTest
public class AmaizeTestData {

    /** Insert a representative set of Accounts, Opportunities, and Headroom rows. */
    public static void makeAll() {
        // ---------------------------------------------------------------------------------
        // This factory has to survive TWO pieces of customer-org automation that don't exist
        // in a clean scratch org, WITHOUT disabling any of it:
        //
        //  1. Account validation rules (billing address required, account guardian required,
        //     etc.). We satisfy them: Organization record type, a guardian Contact, and a
        //     non-US billing city + country.
        //
        //  2. An "Opportunity: After Save Flow" that on every save (a) tries to send a
        //     templated email when Amount is set — which fails in a test transaction because
        //     there's no recipient — and (b) REWRITES Opportunity.Name to
        //     "<Account Name>-<CloseDate year>-". The agent matches grants by name, so to keep
        //     the searchable tokens we give each grant its OWN funder account whose NAME carries
        //     those tokens, and we set Amount/Probability in a follow-up update (not on insert).
        // ---------------------------------------------------------------------------------
        Id orgRtId = businessAccountRecordTypeId();

        // The "grant name" the agent should be able to match lives in the ACCOUNT name, because
        // the customer flow rebuilds the Opportunity name as "<Account Name>-<year>-".
        //
        // GrantSpec carries a `program` (the restriction's Business_Unit__c) alongside the
        // legacy `theme` (Opportunity.Theme_Tag__c). PROGRAM is what the headroom actions now
        // source. Restriction__c.Business_Unit__c is a COUNTRY-DEPENDENT restricted picklist:
        // its specific values are country-suffixed ("Core Program - KE" is valid only when
        // Restriction_Country__c = Kenya; "Farm Input Sales - RW" only for Rwanda), while the
        // base names ("Core Program") are valid only for "No Country Restriction". So the demo
        // restrictions use the suffixed variant valid for each country. Those suffixed programs
        // still resolve to the base-named Budget_Line__c rows the factory inserts below, because
        // AmaizeCheckHeadroom.programMatches() treats a base name and its "- <code>" variant as
        // the same program — so the happy path and the competing-grant logic still reach real
        // verdicts. Theme_Tag__c is kept populated as-is so AmaizeSearchSimilarGrants (which
        // still keys off it) is unaffected; the new grants use the "Agroforestry/Tree" theme to
        // avoid shifting the Kenya/Core Program and Kenya/Carbon search counts those tests assert on.
        List<GrantSpec> specs = new List<GrantSpec>{
            new GrantSpec('Greenfield Kenya Core Program', 'Kenya', 'Core Program - KE', 'Core Program', 'Proposal',
                Date.newInstance(2027, 9, 30), 750000, 60, 'Jeremy Osir'),
            new GrantSpec('Nordic Climate Rwanda Agroforestry', 'Rwanda', 'Farm Input Sales - RW', 'Agroforestry/Tree', 'Closed Won',
                Date.newInstance(2027, 3, 31), 500000, 100, 'Caroline Fong'),
            // Single country + single specific program (rule 2a happy path): Kenya / Core Program - KE.
            new GrantSpec('Continental Dev Bank Kenya Carbon', 'Kenya', 'Core Program - KE', 'Carbon', 'Negotiation',
                Date.newInstance(2027, 8, 30), 2000000, 75, 'Jeremy Osir'),
            // A second Kenya Core grant so "search" can return more than one match.
            new GrantSpec('Second Kenya Core Program', 'Kenya', 'Core Program - KE', 'Core Program', 'Qualification',
                Date.newInstance(2027, 6, 1), 200000, 30, 'Jeremy Osir'),
            // A Closed Lost grant that must be EXCLUDED from competing/search results.
            new GrantSpec('Lost Kenya Core Program', 'Kenya', 'Core Program - KE', 'Core Program', 'Closed Lost',
                Date.newInstance(2027, 1, 1), 999000, 0, 'Jeremy Osir'),
            // Rule 2b: ONE country (Kenya), MULTIPLE specific programs (Core Program - KE +
            // Field Building - KE) — get_opportunity_context should return Kenya and ask which program.
            new GrantSpec('Twin Program Kenya', 'Kenya', 'Core Program - KE', 'Agroforestry/Tree', 'Proposal',
                Date.newInstance(2027, 5, 15), 300000, 50, 'Jeremy Osir'),
            // Rule 2c: ONE country (Kenya), NO specific program (Business_Unit__c is the
            // "No Purpose Restriction" sentinel) — return Kenya and ask which program.
            new GrantSpec('No Purpose Kenya', 'Kenya', 'No Purpose Restriction', 'Agroforestry/Tree', 'Proposal',
                Date.newInstance(2027, 4, 10), 150000, 40, 'Jeremy Osir')
        };
        // Greenfield is eligible in Kenya (Core Program - KE) AND Rwanda (Farm Input Sales - RW),
        // so it exercises the "ask the RM which country" path (rule 2d) — headroom is per country.
        specs.get(0).secondCountry = 'Rwanda';
        specs.get(0).secondProgram = 'Farm Input Sales - RW';
        // Twin Program grant: a second restriction in the SAME country (Kenya) with a
        // DIFFERENT program (Field Building - KE), so the grant spans two programs in one country.
        specs.get(5).secondCountry = 'Kenya';
        specs.get(5).secondProgram = 'Field Building - KE';

        // One guardian Contact shared by all the funder accounts.
        Contact guardian = new Contact(LastName = 'A-maize-ing Demo Guardian');
        insert guardian;

        // One funder account per grant, named with the searchable tokens.
        List<Account> funders = new List<Account>();
        for (GrantSpec sp : specs) {
            Account a = new Account(
                Name = sp.name, Type = 'Foundation',
                Account_Guardian__c = guardian.Id, BillingCity = 'Nairobi', BillingCountry = 'Kenya');
            if (orgRtId != null) a.RecordTypeId = orgRtId;
            funders.add(a);
        }
        insert funders;

        // Insert grants WITHOUT Amount/Probability so the insert-time email step does not fire.
        List<Opportunity> grants = new List<Opportunity>();
        for (Integer i = 0; i < specs.size(); i++) {
            GrantSpec sp = specs[i];
            grants.add(new Opportunity(
                Name = sp.name, AccountId = funders[i].Id,
                Country_Tag__c = sp.country, Theme_Tag__c = sp.theme, StageName = sp.stage,
                CloseDate = sp.closeDate, Guardian__c = sp.guardian));
        }
        insert grants;

        // Backfill Amount/Probability via update (the insert-time flow does not refire on update).
        for (Integer i = 0; i < specs.size(); i++) {
            grants[i].Amount = specs[i].amount;
            grants[i].Probability = specs[i].probability;
        }
        update grants;

        // ---------------------------------------------------------------------------------
        // GiftCommitment + Restriction path — the REAL way a grant's eligible country is
        // recorded: Opportunity <- GiftCommitment <- Restriction__c.Restriction_Country__c.
        // AmaizeGetOpportunityContext and AmaizeCheckHeadroom source country from here, NOT
        // from Opportunity.Country_Tag__c, so the demo grants need this chain to be found.
        // ---------------------------------------------------------------------------------
        List<GiftCommitment> gcs = new List<GiftCommitment>();
        for (Integer i = 0; i < specs.size(); i++) {
            gcs.add(new GiftCommitment(
                Name = 'AMAIZE GC: ' + specs[i].name,
                DonorId = funders[i].Id,
                OpportunityId = grants[i].Id,
                Status = 'Active'));
        }
        insert gcs;

        List<Restriction__c> restrictions = new List<Restriction__c>();
        for (Integer i = 0; i < specs.size(); i++) {
            restrictions.add(newRestriction(gcs[i].Id, specs[i].country, specs[i].program));
            if (specs[i].secondCountry != null) {
                restrictions.add(newRestriction(gcs[i].Id, specs[i].secondCountry, specs[i].secondProgram));
            }
        }
        insert restrictions;

        // Headroom rows: one GREEN (Kenya Core), one RED (Rwanda Tree), one AMBER (Kenya Carbon).
        insert new List<Headroom_Record__c>{
            new Headroom_Record__c(Name = 'AMAIZE: Kenya - Core Program - 2027',
                Country__c = 'Kenya', Program__c = 'Core Program', Year__c = 2027,
                Budgeted_Cost__c = 4200000, Secured_Restricted__c = 3100000,
                Prob_Weighted_Restricted__c = 3550000, Likely30_Restricted__c = 3850000,
                Likely50_Restricted__c = 3700000),
            new Headroom_Record__c(Name = 'AMAIZE: Rwanda - Agroforestry/Tree - 2027',
                Country__c = 'Rwanda', Program__c = 'Agroforestry/Tree', Year__c = 2027,
                Budgeted_Cost__c = 900000, Secured_Restricted__c = 1050000,
                Prob_Weighted_Restricted__c = 1050000, Likely30_Restricted__c = 1050000,
                Likely50_Restricted__c = 1050000),
            new Headroom_Record__c(Name = 'AMAIZE: Kenya - Carbon - 2027',
                Country__c = 'Kenya', Program__c = 'Carbon', Year__c = 2027,
                Budgeted_Cost__c = 1800000, Secured_Restricted__c = 500000,
                Prob_Weighted_Restricted__c = 2000000, Likely30_Restricted__c = 2000000,
                Likely50_Restricted__c = 2000000)
        };

        // ---------------------------------------------------------------------------------
        // Budget_Scenario__c / Budget_Line__c fixtures — the REAL headroom data model that
        // AmaizeCheckHeadroom / AmaizeFindPrograms now read from. BusinessUnit__c is a
        // RESTRICTED picklist of One Acre Fund's actual business units (no "Carbon" or
        // "Agroforestry" values exist), so these fixtures use real values and are kept
        // separate from the Headroom_Record__c/Opportunity theme names above by design —
        // none of the three BusinessUnit__c values below overlap with an existing grant's
        // Theme_Tag__c, so AmaizeSearchSimilarGrantsTest's exact match counts are unaffected.
        //
        // One current scenario, with lines covering all three Headroom_status__c tri-states:
        //   Kenya  / Core Program      -> Headroom Available      ($1.1M >= $250K)
        //   Rwanda / Farm Input Sales  -> Headroom Unavailable     (-$150K, negative)
        //   Kenya  / Field Building    -> Some Headroom Available  ($100K, positive but < $250K)
        // ---------------------------------------------------------------------------------
        Budget_Scenario__c scenario = new Budget_Scenario__c(
            Scenario_Type__c = 'Final Budget',
            Effective_Date__c = Date.newInstance(2027, 1, 1),
            External_Key__c = 'AMAIZE-DEMO-SCENARIO-2027',
            Is_Current_Scenario__c = true,
            Fiscal_Year__c = '2027');
        insert scenario;

        // Budget_Line__c.Name is an auto-number field (not writeable) — identity for these
        // demo rows is carried by Country__c/BusinessUnit__c/Fiscal_Year__c instead.
        insert new List<Budget_Line__c>{
            new Budget_Line__c(
                Budget_Scenario__c = scenario.Id, Country__c = 'Kenya', BusinessUnit__c = 'Core Program',
                Fiscal_Year__c = '2027', Budget_Amount__c = -4200000, Secured_Funding__c = 3100000),
            new Budget_Line__c(
                Budget_Scenario__c = scenario.Id, Country__c = 'Rwanda', BusinessUnit__c = 'Farm Input Sales',
                Fiscal_Year__c = '2027', Budget_Amount__c = -900000, Secured_Funding__c = 1050000),
            new Budget_Line__c(
                Budget_Scenario__c = scenario.Id, Country__c = 'Kenya', BusinessUnit__c = 'Field Building',
                Fiscal_Year__c = '2027', Budget_Amount__c = -1800000, Secured_Funding__c = 1700000)
        };
    }

    /**
     * Build a Restriction row carrying the eligible country AND program. Both
     * Restriction_Country__c and Business_Unit__c (the program) are meaningful to the
     * A-maize-ing actions. `program` must be a valid Business_Unit__c picklist value FOR
     * the given country: Business_Unit__c is a restricted picklist DEPENDENT on
     * Restriction_Country__c, so a specific program must be the country-suffixed variant
     * valid for that country ("Core Program - KE"/"Field Building - KE" for Kenya,
     * "Farm Input Sales - RW" for Rwanda — the base names are valid only for
     * "No Country Restriction"), or the broadly-valid "No Purpose Restriction" sentinel.
     *
     * Restriction__c also has several required cost-coding picklists that are irrelevant to
     * headroom matching. They are restricted AND dependent (Cost_Category__c is controlled
     * by Cost_Type__c, etc.), so only certain combinations are valid on insert; this set is
     * verified valid field-by-field against the org's picklists and left at those values.
     */
    private static Restriction__c newRestriction(Id giftCommitmentId, String country, String program) {
        return new Restriction__c(
            Gift_Commitment__c = giftCommitmentId,
            Restriction_Country__c = country,
            Incremental_Funds__c = 'No',
            Is_this_a_grant_to_a_sub_grantee__c = 'No',
            Business_Unit__c = program,
            Sub_Unit__c = 'N/A',
            Cost_Type__c = 'N/A',
            Cost_Category__c = 'N/A',
            Department_Name__c = 'N/A',
            Line_Item__c = 'N/A');
    }

    /** Return the Id of the current Budget_Scenario__c created by makeAll(), for tests
     *  that need to insert extra Budget_Line__c rows under the same current scenario. */
    public static Id currentScenarioId() {
        return [SELECT Id FROM Budget_Scenario__c WHERE Is_Current_Scenario__c = true LIMIT 1].Id;
    }

    /** A grant fixture spec: the searchable name plus the demo signal values. */
    private class GrantSpec {
        String name;
        String country;
        String program;         // Restriction__c.Business_Unit__c for the primary restriction
        String theme;           // Opportunity.Theme_Tag__c (legacy; kept for unrelated tests)
        String stage;
        Date closeDate;
        Decimal amount;
        Decimal probability;
        String guardian;
        String secondCountry;   // optional: a second eligible country (multi-country path)
        String secondProgram;   // optional: the program on the second restriction
        GrantSpec(String name, String country, String program, String theme, String stage,
                  Date closeDate, Decimal amount, Decimal probability, String guardian) {
            this.name = name;
            this.country = country;
            this.program = program;
            this.theme = theme;
            this.stage = stage;
            this.closeDate = closeDate;
            this.amount = amount;
            this.probability = probability;
            this.guardian = guardian;
        }
    }

    /**
     * Return the Id of a business (non-person) Account record type, or null if the org
     * has no record types / person accounts disabled. Picks "Organization" by name when
     * present, otherwise any non-person Account record type.
     */
    private static Id businessAccountRecordTypeId() {
        Map<String, Schema.RecordTypeInfo> byName =
            Account.SObjectType.getDescribe().getRecordTypeInfosByDeveloperName();
        Schema.RecordTypeInfo org = byName.get('Organization');
        if (org != null && org.isAvailable()) {
            return org.getRecordTypeId();
        }
        // Fall back to any available, non-master record type.
        for (Schema.RecordTypeInfo rt : byName.values()) {
            if (rt.isAvailable() && !rt.isMaster()) {
                return rt.getRecordTypeId();
            }
        }
        return null;
    }

    /** Return the Id of a seeded grant by (partial) name, for tests that need it. */
    public static Id oppId(String namePart) {
        for (Opportunity o : [SELECT Id, Name FROM Opportunity]) {
            if (o.Name.containsIgnoreCase(namePart)) return o.Id;
        }
        return null;
    }
}