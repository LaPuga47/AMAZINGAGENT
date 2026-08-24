/**
 * Reads Feature_Flag__mdt to enable/disable agent actions and subagents per
 * environment without a code change. Defaults to ENABLED when no record exists
 * (absence must not silently break a read-only capability). Tests inject values
 * via setOverride() since custom metadata cannot be inserted in a test.
 */
public inherited sharing class FeatureFlag {
    @TestVisible
    private static Map<String, Boolean> overrides = new Map<String, Boolean>();

    public static Boolean isEnabled(String developerName) {
        if (overrides.containsKey(developerName)) {
            return overrides.get(developerName);
        }
        Feature_Flag__mdt flag = Feature_Flag__mdt.getInstance(developerName);
        return flag == null ? true : flag.Is_Active__c;
    }

    @TestVisible
    private static void setOverride(String developerName, Boolean value) {
        overrides.put(developerName, value);
    }
}