@isTest
private class SummaryTextTest {
    @isTest
    static void moneyFormatsAndHandlesNull() {
        System.assertEquals('USD 1,234.56', SummaryText.money('USD', 1234.56), 'currency + 2dp');
        System.assertEquals('N/A', SummaryText.money('USD', null), 'null -> N/A');
        System.assertEquals('1,000', SummaryText.money('', 1000), 'blank currency, no prefix');
        System.assertEquals(null, SummaryText.moneyOrNull('USD', null), 'moneyOrNull null -> null');
        System.assertEquals('USD 5', SummaryText.moneyOrNull('USD', 5), 'moneyOrNull value');
    }

    @isTest
    static void dateAndBreakdowns() {
        System.assertEquals('N/A', SummaryText.dateOrNa(null), 'null date');
        System.assertEquals('2026-07-10', SummaryText.dateOrNa(Date.newInstance(2026, 7, 10)), 'iso date');

        Map<String, Integer> counts = new Map<String, Integer>{ 'Paid' => 2 };
        Map<String, Decimal> amounts = new Map<String, Decimal>{ 'Paid' => 300 };
        System.assertEquals('Paid: 2 (USD 300)', SummaryText.statusBreakdown('USD', counts, amounts), 'status breakdown');
        System.assertEquals('None', SummaryText.statusBreakdown('USD', new Map<String, Integer>(), amounts), 'empty -> None');
        System.assertEquals('Sent: 5', SummaryText.countBreakdown(new Map<String, Integer>{ 'Sent' => 5 }), 'count breakdown');
        System.assertEquals('None', SummaryText.countBreakdown(new Map<String, Integer>()), 'empty count -> None');
    }

    @isTest
    static void sanitizeStripsUrlsIdsAndTokens() {
        // URL_Redacted token removed
        System.assert(!SummaryText.sanitize('See URL_Redacted here').contains('URL_Redacted'), 'token removed');
        // absolute URL removed
        System.assert(
            !SummaryText.sanitize('Open https://x--1afull.sandbox.my.salesforce.com/006ABC now').contains('http'),
            'absolute url removed'
        );
        // relative lightning path removed
        System.assert(
            !SummaryText.sanitize('Go /lightning/r/Opportunity/006ABC/view').contains('/lightning/'),
            'lightning path removed'
        );
        // dangling "Link:" fragment removed
        String cleaned = SummaryText.sanitize('Acme Grant — Stage: Won, Link: https://x/006ABC');
        System.assert(!cleaned.containsIgnoreCase('Link:'), 'link label removed: ' + cleaned);
        System.assert(cleaned.contains('Acme Grant'), 'content preserved');
        // legitimate content is untouched (incl. long transaction-style names and amounts)
        String kept = SummaryText.sanitize('• Name: GT25626608788, Amount: USD 107,550,000');
        System.assertEquals('• Name: GT25626608788, Amount: USD 107,550,000', kept, 'clean text unchanged');
        // null-safe
        System.assertEquals(null, SummaryText.sanitize(null), 'null passthrough');
    }
}