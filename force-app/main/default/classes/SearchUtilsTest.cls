@isTest
private class SearchUtilsTest {
    @isTest
    static void clampLimitAppliesDefaultsAndBounds() {
        System.assertEquals(10, SearchUtils.clampLimit(null));
        System.assertEquals(10, SearchUtils.clampLimit(0));
        System.assertEquals(5, SearchUtils.clampLimit(5));
        System.assertEquals(50, SearchUtils.clampLimit(999));
        System.assertEquals(3, SearchUtils.clampLimit(3, 10, 50));
    }

    @isTest
    static void escapeLikeNeutralizesWildcards() {
        System.assertEquals('a\\%b\\_c', SearchUtils.escapeLike('a%b_c'));
        System.assertEquals('', SearchUtils.escapeLike('  '));
    }

    @isTest
    static void forContainsWrapsTerm() {
        System.assertEquals('%', SearchUtils.forContains(''));
        System.assertEquals('%x%', SearchUtils.forContains('  x '));
    }
}