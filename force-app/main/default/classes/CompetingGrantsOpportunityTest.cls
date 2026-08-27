/**
 * CompetingGrantsOpportunityTest — the Opportunity-start competition path: resolve a grant,
 * expand to the governed scopes its allocations touch, and analyze competition per scope
 * (multi-scope grants analyzed separately, not collapsed). Plus the action rendering and the
 * not-found / no-allocation paths.
 */
@isTest
private class CompetingGrantsOpportunityTest {

    @TestSetup
    static void setup() {
        Budget_Scenario__c s = HeadroomTestData.makeCurrentScenario();
        HeadroomTestData.makeLine(s.Id, 'Kenya', 'Core Program - KE', 'N/A', 'N/A', 'N/A', 'N/A', -5000000, 0, 0, 0);
        HeadroomTestData.makeLine(s.Id, 'Rwanda', 'Core Program - RW', 'N/A', 'N/A', 'N/A', 'N/A', -2000000, 0, 0, 0);
    }

    private static Id lineId(String bu) {
        return [SELECT Id FROM Budget_Line__c WHERE BusinessUnit__c = :bu LIMIT 1].Id;
    }
    private static String focusOppName() {
        return [SELECT Name FROM Opportunity WHERE Account.Name LIKE 'HR Multi Donor%' LIMIT 1].Name;
    }

    @isTest
    static void resolvesScopeAndFindsCompetitor() {
        // Focus grant allocated 500k to Core Program - KE; a competitor allocated 700k to the same scope.
        HeadroomTestData.makeOppAllocations('Pipeline', new List<Id>{ lineId('Core Program - KE') },
            500000, 'Kenya', 'Core Program - KE', 800000, 'RM A');
        HeadroomTestData.makeAllocations(new List<HeadroomTestData.AllocSpec>{
            new HeadroomTestData.AllocSpec('Pipeline', 700000)
        }, lineId('Core Program - KE'), 'Kenya', 'Core Program - KE');
        String name = focusOppName();

        Test.startTest();
        OpportunityCompetition a = new CompetingGrantsService().analyzeForOpportunity(name);
        Test.stopTest();

        System.assertEquals(OpportunityCompetition.Status.FOUND, a.status);
        System.assertEquals(1, a.scopesTouched);
        System.assertEquals(1, a.scopes.size());
        OpportunityCompetition.ScopeCompetition sc = a.scopes[0];
        System.assertEquals('Core Program', sc.category);
        System.assertEquals('Kenya', sc.country);
        System.assertEquals(500000, sc.focusExposure, 'focus grant exposure to this scope');
        System.assertEquals(2, sc.competition.grants.size(), 'focus + one competitor consume this scope');
    }

    @isTest
    static void multiScopeGrantAnalyzedSeparately() {
        // One grant with restrictions in two countries -> two governed scopes (Core Program in
        // Kenya and Rwanda). Each restriction's match key links its allocation to its own line
        // (mirrors real data), so the analysis expands into two separate scopes.
        Account donor = HeadroomTestData.makeDonorAccount('Multi Scope Donor');
        Opportunity opp = new Opportunity(Name = 'Multi Scope Grant', AccountId = donor.Id,
            Country_Tag__c = 'Kenya', Theme_Tag__c = 'Agroforestry/Tree', StageName = 'Negotiation',
            CloseDate = Date.newInstance(2027, 6, 1), Guardian__c = 'RM A');
        insert opp;
        opp.Probability = 25; update opp;   // Pipeline
        GiftCommitment gc = new GiftCommitment(Name = 'MS GC', DonorId = donor.Id,
            OpportunityId = opp.Id, Status = 'Active');
        insert gc;
        Restriction__c rKE = restr(gc.Id, 'Kenya', 'Core Program - KE');
        Restriction__c rRW = restr(gc.Id, 'Rwanda', 'Core Program - RW');
        insert new List<Restriction__c>{ rKE, rRW };
        Fund__c f = new Fund__c(Name = HeadroomTestData.FY); insert f;
        // No direct Budget_Line__c — the linking flow matches each restriction's key to its line.
        insert new List<Allocation__c>{
            new Allocation__c(Restriction__c = rKE.Id, Fund__c = f.Id, Funds_Allocated__c = 300000),
            new Allocation__c(Restriction__c = rRW.Id, Fund__c = f.Id, Funds_Allocated__c = 300000)
        };
        String name = [SELECT Name FROM Opportunity WHERE Account.Name LIKE 'Multi Scope Donor%' LIMIT 1].Name;

        Test.startTest();
        OpportunityCompetition a = new CompetingGrantsService().analyzeForOpportunity(name);
        Test.stopTest();

        System.assertEquals(OpportunityCompetition.Status.FOUND, a.status);
        System.assertEquals(2, a.scopesTouched, 'Kenya and Rwanda Core Program are separate scopes');
        Set<String> countries = new Set<String>();
        for (OpportunityCompetition.ScopeCompetition sc : a.scopes) { countries.add(sc.country); }
        System.assert(countries.contains('Kenya') && countries.contains('Rwanda'), countries.toString());
    }

    private static Restriction__c restr(Id gcId, String country, String bu) {
        return new Restriction__c(Gift_Commitment__c = gcId, Restriction_Country__c = country,
            Business_Unit__c = bu, Sub_Unit__c = 'N/A', Cost_Type__c = 'N/A', Department_Name__c = 'N/A',
            Cost_Category__c = 'N/A', Line_Item__c = 'N/A', Incremental_Funds__c = 'No',
            Is_this_a_grant_to_a_sub_grantee__c = 'No');
    }

    @isTest
    static void notFoundForUnknownName() {
        OpportunityCompetition a = new CompetingGrantsService().analyzeForOpportunity('Nonexistent Grant Zzzq');
        System.assertEquals(OpportunityCompetition.Status.NOT_FOUND, a.status);
    }

    @isTest
    static void actionRendersPerScopeWithLinks() {
        HeadroomTestData.makeOppAllocations('Pipeline', new List<Id>{ lineId('Core Program - KE') },
            500000, 'Kenya', 'Core Program - KE', 800000, 'RM A');
        HeadroomTestData.makeAllocations(new List<HeadroomTestData.AllocSpec>{
            new HeadroomTestData.AllocSpec('Pipeline', 700000)
        }, lineId('Core Program - KE'), 'Kenya', 'Core Program - KE');
        String name = focusOppName();

        AmaizeOpportunityCompetition.Request req = new AmaizeOpportunityCompetition.Request();
        req.opportunityName = name;
        Test.startTest();
        AmaizeOpportunityCompetition.Result res = AmaizeOpportunityCompetition.analyze(
            new List<AmaizeOpportunityCompetition.Request>{ req })[0];
        Test.stopTest();

        System.assertEquals(true, res.found);
        System.assert(res.summary.contains('Competition for'), res.summary);
        System.assert(res.summary.contains('Core Program · Kenya'), res.summary);
        System.assert(res.summary.contains('exposure here'), res.summary);
        System.assert(res.summary.contains('/lightning/r/Opportunity/'), 'record link present: ' + res.summary);
    }
}
