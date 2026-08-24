@isTest
private class ValidationUtilsTest {
    @isTest
    static void isBlankDetectsEmpty() {
        System.assertEquals(true, ValidationUtils.isBlank('  '));
        System.assertEquals(false, ValidationUtils.isBlank('x'));
    }

    @isTest
    static void isValidIdDistinguishesIds() {
        System.assertEquals(true, ValidationUtils.isValidId(UserInfo.getUserId()));
        System.assertEquals(false, ValidationUtils.isValidId('not-an-id'));
        System.assertEquals(false, ValidationUtils.isValidId(''));
    }

    @isTest
    static void requireThrowsWhenFalse() {
        try {
            ValidationUtils.require(false, 'must be true');
            System.assert(false, 'Expected ValidationException');
        } catch (ValidationException e) {
            System.assertEquals('must be true', e.getMessage());
        }
        ValidationUtils.require(true, 'ok'); // should not throw
    }
}