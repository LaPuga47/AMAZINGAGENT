@isTest
private class AccountClassificationTest {
    private static Account acct(String payload) {
        return (Account) JSON.deserialize(payload, Account.class);
    }

    @isTest
    static void personAccountClassifies() {
        Account a = acct(
            '{"Id":"001000000000001AAA","Name":"Jane Donor","IsPersonAccount":true,' +
            '"RecordType":{"Name":"Person Account","DeveloperName":"PersonAccount"}}'
        );
        System.assertEquals('Person Account', AccountClassification.category(a));
        System.assert(AccountClassification.isPerson(a), 'isPerson');
    }

    @isTest
    static void organizationAccountClassifies() {
        Account a = acct(
            '{"Id":"001000000000002AAA","Name":"Acme Corp","Type":"Corporation",' +
            '"RecordType":{"Name":"Organization","DeveloperName":"Organization"}}'
        );
        System.assertEquals('Organization Account', AccountClassification.category(a));
        System.assert(AccountClassification.isOrganization(a), 'isOrg');
    }

    @isTest
    static void householdAccountClassifiesFromType() {
        Account a = acct(
            '{"Id":"001000000000003AAA","Name":"The Smith Household","Type":"Household",' +
            '"RecordType":{"Name":"Organization","DeveloperName":"Organization"}}'
        );
        System.assertEquals('Household Account', AccountClassification.category(a));
        System.assert(AccountClassification.isHousehold(a), 'isHousehold');
    }

    @isTest
    static void missingTypeButValidRecordTypeClassifiesAsOrganization() {
        Account a = acct(
            '{"Id":"001000000000004AAA","Name":"No Type Org",' +
            '"RecordType":{"Name":"Organization","DeveloperName":"Organization"}}'
        );
        System.assertEquals('Organization Account', AccountClassification.category(a));
    }

    @isTest
    static void unclassifiableFallsBackToOther() {
        Account a = acct('{"Id":"001000000000005AAA","Name":"Mystery"}');
        System.assertEquals('Other Account', AccountClassification.category(a));
        System.assertEquals('Other Account', AccountClassification.category(null), 'null account -> Other');
    }
}