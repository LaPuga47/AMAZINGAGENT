@isTest
private class EntityMatcherTest {
    @isTest
    static void scoresByMatchQuality() {
        System.assertEquals(100, EntityMatcher.score('abc', 'abc'), 'exact');
        System.assertEquals(100, EntityMatcher.score('ABC', 'abc'), 'case-insensitive exact');
        System.assertEquals(75, EntityMatcher.score('ab', 'abcd'), 'starts-with');
        System.assertEquals(50, EntityMatcher.score('cd', 'abcde'), 'contains');
        System.assertEquals(0, EntityMatcher.score('xyz', 'abc'), 'no match');
        System.assertEquals(0, EntityMatcher.score('', 'abc'), 'blank term');
    }
}