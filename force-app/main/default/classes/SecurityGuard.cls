/**
 * Centralized FLS/CRUD helpers so no layer over-shares donor/financial data.
 * Selectors query WITH USER_MODE; this guard covers the cases where an explicit
 * accessibility check or field strip is needed outside a query.
 */
public inherited sharing class SecurityGuard {
    public static Boolean isReadable(SObjectType sobjType) {
        return sobjType.getDescribe().isAccessible();
    }

    public static void assertReadable(SObjectType sobjType) {
        if (!isReadable(sobjType)) {
            throw new AppException('You do not have read access to ' + sobjType.getDescribe().getName() + '.');
        }
    }

    /** Returns copies of the records containing only fields the running user can read. */
    public static List<SObject> stripRead(List<SObject> records) {
        return Security.stripInaccessible(AccessType.READABLE, records).getRecords();
    }
}