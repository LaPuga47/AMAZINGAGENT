@isTest
private class AppExceptionTest {
    @isTest
    static void appException_carriesMessage() {
        try {
            throw new AppException('boom');
        } catch (AppException e) {
            System.assertEquals('boom', e.getMessage(), 'Message should round-trip');
        }
    }

    @isTest
    static void validationException_isAnAppException() {
        Boolean caughtAsApp = false;
        try {
            throw new ValidationException('bad input');
        } catch (AppException e) {
            caughtAsApp = true;
            System.assertEquals('bad input', e.getMessage());
        }
        System.assert(caughtAsApp, 'ValidationException should be catchable as AppException');
    }
}