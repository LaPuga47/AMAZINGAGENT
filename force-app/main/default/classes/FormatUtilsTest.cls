@isTest
private class FormatUtilsTest {
    @isTest
    static void formatAmountHandlesNullAndValue() {
        System.assertEquals('', FormatUtils.formatAmount(null));
        String formatted = FormatUtils.formatAmount(1234567.5);
        System.assert(formatted.contains('234'), 'Should render the number: ' + formatted);
    }

    @isTest
    static void formatDateHandlesNullAndValue() {
        System.assertEquals('', FormatUtils.formatDate(null));
        System.assertEquals('2026-07-02', FormatUtils.formatDate(Date.newInstance(2026, 7, 2)));
    }
}