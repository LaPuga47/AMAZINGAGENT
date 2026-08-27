/**
 * HeadroomCategoryResolverTest — the governed HR-001..HR-007 mappings and the
 * not-configured / generic fallbacks. No data required (pure resolution logic).
 */
@isTest
private class HeadroomCategoryResolverTest {

    @isTest
    static void coreProgramSynonymsMapToCoreProgramBase() {
        for (String s : new List<String>{ 'Core Program', 'core field program', 'Core (Field) Program', 'Field Program' }) {
            HeadroomCategoryResolver.Rule r = HeadroomCategoryResolver.resolve(s);
            System.assertEquals(HeadroomCategoryResolver.Mode.NORMAL, r.mode, s);
            System.assertEquals('Core Program', r.businessUnitBase, s);
            System.assertEquals(null, r.department, s);
        }
    }

    @isTest
    static void ruralRetailRequiresFarmInputSalesAndDepartment() {
        HeadroomCategoryResolver.Rule r = HeadroomCategoryResolver.resolve('RRT');
        System.assertEquals('Farm Input Sales', r.businessUnitBase);
        System.assertEquals('Rural Retail', r.department);
    }

    @isTest
    static void marketAccessAndTreesMapToDepartments() {
        System.assertEquals('Market Access', HeadroomCategoryResolver.resolve('Market Access Program').department);
        System.assertEquals('Trees', HeadroomCategoryResolver.resolve('trees').department);
        System.assertEquals('Farm Input Sales', HeadroomCategoryResolver.resolve('TRE').businessUnitBase);
    }

    @isTest
    static void systemsChangeVariantsMapToSystemsChange() {
        for (String s : new List<String>{ 'System Change', 'Systems Change Extension', 'System Change Extension & Other Programs' }) {
            HeadroomCategoryResolver.Rule r = HeadroomCategoryResolver.resolve(s);
            System.assertEquals('Systems Change', r.businessUnitBase, s);
            System.assertEquals(HeadroomCategoryResolver.Mode.NORMAL, r.mode, s);
        }
    }

    @isTest
    static void unrestrictedAndWorkingCapitalAreZero() {
        System.assertEquals(HeadroomCategoryResolver.Mode.ZERO, HeadroomCategoryResolver.resolve('Unrestricted').mode);
        System.assertEquals(HeadroomCategoryResolver.Mode.ZERO, HeadroomCategoryResolver.resolve('Working Capital').mode);
    }

    @isTest
    static void otherAndMiscellaneousAreNotConfigured() {
        System.assertEquals(HeadroomCategoryResolver.Mode.NOT_CONFIGURED, HeadroomCategoryResolver.resolve('Miscellaneous').mode);
        System.assertEquals(HeadroomCategoryResolver.Mode.NOT_CONFIGURED, HeadroomCategoryResolver.resolve('Other Support Departments').mode);
    }

    @isTest
    static void unknownFallsBackToGenericBusinessUnit() {
        HeadroomCategoryResolver.Rule r = HeadroomCategoryResolver.resolve('Business Operations');
        System.assertEquals(HeadroomCategoryResolver.Mode.GENERIC, r.mode);
        System.assertEquals('Business Operations', r.businessUnitBase);
    }

    @isTest
    static void blankResolvesToNull() {
        System.assertEquals(null, HeadroomCategoryResolver.resolve('   '));
    }
}
