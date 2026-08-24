/**
 * HeadroomAnalysis — the outcome of trying to identify a single Budget Line and read
 * its headroom. Carries exactly one of four states so the calling action can compose
 * the right response without re-running any logic:
 *
 *   FOUND       — exactly one Budget Line matched; `line` + `allocations` are set.
 *   AMBIGUOUS   — several Budget Lines matched; `candidates` + `distinguishingDimensions`
 *                 tell the user how they differ so they can pick.
 *   NOT_FOUND   — nothing matched the supplied dimensions (never fabricate headroom).
 *   NEEDS_INFO  — the request lacked the minimum dimensions to search specifically.
 *
 * Plain data holder — no SOQL, no DML.
 */
public with sharing class HeadroomAnalysis {

    public enum Status { FOUND, AMBIGUOUS, NOT_FOUND, NEEDS_INFO }

    public Status status;

    // The normalized dimensions actually used for the search (for honest "I looked by ..." text).
    public BudgetLineDimensions requested;

    // FOUND
    public Budget_Line__c line;
    public AllocationBreakdown allocations;
    public String allocationSource;  // 'direct' | 'match-key' | 'none'

    // AMBIGUOUS
    public List<Budget_Line__c> candidates;
    public List<String> distinguishingDimensions;

    // NEEDS_INFO
    public List<String> missingDimensions;
    public Boolean subUnitMissing = false;
}
