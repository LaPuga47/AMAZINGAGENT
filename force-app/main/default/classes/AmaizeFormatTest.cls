/**
 * AmaizeFormatTest — the spaceFollowUp helper: widen the gap before a trailing follow-up
 * question to two blank lines, only touch the final follow-up line, be idempotent, and leave
 * non-follow-up text alone.
 */
@isTest
private class AmaizeFormatTest {

    @isTest
    static void widensTheGapBeforeATrailingFollowUp() {
        String s = 'Kenya Trees has $473K of available Headroom in 2027.\n\nWould you like to see the grants?';
        String out = AmaizeFormat.spaceFollowUp(s);
        System.assert(out.contains('2027.\n\n\nWould'), out.replace('\n', '[NL]'));
        System.assert(out.endsWith('grants?'), out);
    }

    @isTest
    static void isIdempotent() {
        String once = AmaizeFormat.spaceFollowUp('Answer here.\n\nWould you like more?');
        String twice = AmaizeFormat.spaceFollowUp(once);
        System.assertEquals(once, twice, 'applying twice must not keep widening the gap');
        System.assertEquals(1, once.countMatches('\n\n\n'), 'exactly one two-blank-line gap: ' + once.replace('\n', '[NL]'));
    }

    @isTest
    static void leavesNonFollowUpTextAlone() {
        // No trailing question -> unchanged.
        String noQ = 'Just a statement.\n\nAnother statement.';
        System.assertEquals(noQ, AmaizeFormat.spaceFollowUp(noQ));
        // Only the FINAL follow-up gap is widened; an earlier section break stays a single blank line.
        String multi = 'Line one.\n\nLine two.\n\nWould you like details?';
        String out = AmaizeFormat.spaceFollowUp(multi);
        System.assert(out.contains('Line one.\n\nLine two.'), 'section break untouched: ' + out.replace('\n', '[NL]'));
        System.assert(out.contains('Line two.\n\n\nWould'), 'only the follow-up gap widened: ' + out.replace('\n', '[NL]'));
    }

    @isTest
    static void handlesBlankInput() {
        System.assertEquals(null, AmaizeFormat.spaceFollowUp(null));
        System.assertEquals('', AmaizeFormat.spaceFollowUp(''));
    }
}
