@isTest
private class FeatureFlagTest {
    @isTest
    static void overrideEnabled() {
        FeatureFlag.setOverride('SomeAction', true);
        System.assertEquals(true, FeatureFlag.isEnabled('SomeAction'));
    }

    @isTest
    static void overrideDisabled() {
        FeatureFlag.setOverride('SomeAction', false);
        System.assertEquals(false, FeatureFlag.isEnabled('SomeAction'));
    }

    @isTest
    static void defaultsToEnabledWhenUnknown() {
        System.assertEquals(true, FeatureFlag.isEnabled('NoSuchFlag_Unknown'),
            'Absence of a flag record should default to enabled');
    }
}