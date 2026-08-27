/**
 * PortfolioScopeRisk — competition metrics for one governed scope (Headroom category +
 * country + fiscal year), rolled up from the portfolio aggregates. Used to rank collision
 * risk across the portfolio. Plain data holder — no SOQL, no DML.
 */
public with sharing class PortfolioScopeRisk {

    public String category;
    public String country;
    public String fiscalYear;
    public String currencyIsoCode;

    public Integer budgetLineCount = 0;
    public Decimal securedHeadroom = 0;
    public Decimal forecastHeadroom = 0;
    public Decimal combinedCompeting = 0;      // Likely + Pipeline allocation exposure
    public Integer competingAllocationCount = 0;
    public Decimal minimumAdjustmentRequired = 0;  // max(0, combinedCompeting - securedHeadroom)
    public String severity;

    /** Aggregate a budget-line rollup row into this scope. */
    public void addBudgetLines(Decimal securedHeadroomSum, Decimal forecastHeadroomSum, Integer lineCount, String iso) {
        this.securedHeadroom += AmaizeBudgetHeadroom.nz(securedHeadroomSum);
        this.forecastHeadroom += AmaizeBudgetHeadroom.nz(forecastHeadroomSum);
        this.budgetLineCount += (lineCount == null ? 0 : lineCount);
        if (this.currencyIsoCode == null) { this.currencyIsoCode = iso; }
    }

    /** Aggregate a competing-allocation rollup row into this scope. */
    public void addCompeting(Decimal amount, Integer count) {
        this.combinedCompeting += AmaizeBudgetHeadroom.nz(amount);
        this.competingAllocationCount += (count == null ? 0 : count);
    }

    /** Finalize derived metrics once all rows are folded in. */
    public void finalizeMetrics() {
        Decimal excess = combinedCompeting - securedHeadroom;
        minimumAdjustmentRequired = excess > 0 ? excess : 0;
        // Portfolio grain has no probability weighting, so pass 0 for that input (avoids
        // over-escalating every over-headroom scope to Critical; uses the combined-exposure rule).
        severity = CompetingGrantsService.severityFor(securedHeadroom, combinedCompeting, 0);
    }
}
