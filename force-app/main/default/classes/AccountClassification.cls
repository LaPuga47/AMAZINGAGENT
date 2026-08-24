/**
 * Deterministic Account categorization for the Employee Agent. Uses only
 * structured data (IsPersonAccount, RecordType.DeveloperName, Type) — never the
 * Account name. The connected org has two Account record types (PersonAccount,
 * Organization); "Household" is expressed via the Type picklist, not a record type.
 */
public inherited sharing class AccountClassification {
    public static final String PERSON = 'Person Account';
    public static final String ORGANIZATION = 'Organization Account';
    public static final String HOUSEHOLD = 'Household Account';
    public static final String OTHER = 'Other Account';

    private static final Set<String> HOUSEHOLD_TYPES = new Set<String>{ 'Household', 'Individual or Family' };
    private static final String ORG_RECORD_TYPE = 'Organization';

    /** User-facing Account Category, resolved deterministically. */
    public static String category(Account a) {
        if (a == null) {
            return OTHER;
        }
        if (a.IsPersonAccount == true) {
            return PERSON;
        }
        if (String.isNotBlank(a.Type) && HOUSEHOLD_TYPES.contains(a.Type)) {
            return HOUSEHOLD;
        }
        if (recordTypeDeveloperName(a) == ORG_RECORD_TYPE) {
            return ORGANIZATION;
        }
        return OTHER;
    }

    public static Boolean isPerson(Account a) {
        return a != null && a.IsPersonAccount == true;
    }

    public static Boolean isHousehold(Account a) {
        return category(a) == HOUSEHOLD;
    }

    public static Boolean isOrganization(Account a) {
        return category(a) == ORGANIZATION;
    }

    /** RecordType.DeveloperName, guarded against an unqueried/absent RecordType. */
    public static String recordTypeDeveloperName(Account a) {
        return (a == null || a.RecordType == null) ? null : a.RecordType.DeveloperName;
    }

    /** RecordType.Name (label), guarded. */
    public static String recordTypeName(Account a) {
        return (a == null || a.RecordType == null) ? null : a.RecordType.Name;
    }
}