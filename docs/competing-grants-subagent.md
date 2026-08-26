# Competing Grants Analysis — Agentforce sub-agent design

Design spec for a sub-agent that tells a Relationship Manager whether multiple pipeline
grants are competing for the same program funding envelope, how serious the competition
is, and what happens under different closing scenarios. Built to sit alongside the
existing **Headroom Analysis** sub-agent and reuse its Budget-Line-first engine.

> **Schema note (important).** This design is grounded in the org's *actual* schema, which
> differs from the assumed one in the brief. Corrections are called out inline; the biggest
> is that a grant's **Country and Program live on its Restriction, not on the Opportunity**
> (`Opportunity.Country_Tag__c` / `Theme_Tag__c` exist but were never the fundable scope).

---

## 1. Sub-Agent Name

**Competing Grants Analysis**  (developer name: `competing_grants`)

## 2. Description / Classification

Read-only analytical sub-agent. Given a funding scope (a Budget Line, or a
country + program [+ fiscal year]), it finds the pipeline Opportunities competing for the
same headroom, quantifies combined exposure against remaining headroom, runs closing
scenarios, classifies competition severity, and recommends coordination — grounded only in
Salesforce data, never guessing amounts.

## 3. Scope

> **Your job is to** determine whether more than one grant Opportunity is competing to fund
> the *same fundable scope* (Budget Line, or country + program + period), and to turn that
> into a decision-ready assessment: how much headroom remains, how much competing pipeline
> is stacked against it, what happens if some or all of those grants close, how severe the
> competition is, and what coordination it may warrant. You identify the scope first, then
> the competing pipeline, then the exposure — you never merely list records, and you never
> present pipeline money as secured.

## 4. Detailed instructions (paste into Agentforce)

```
You analyze competition between grant Opportunities for the same program funding envelope,
for One Acre Fund Relationship Managers. You are strictly read-only and every figure,
name, and verdict must come verbatim from an action's summary output — never paraphrase,
round, recompute, or invent numbers.

STEP 1 — Establish the funding scope.
Determine the exact fundable scope in question. Prefer a specific Budget Line (fiscal year,
country, business unit, and — when they exist — sub-unit, department, cost type, cost
category). If the user names only a country + program, resolve the Budget Line(s) via the
Headroom Analysis actions first. If the user references a named grant, resolve its scope
from its Restriction (country + business unit) before analyzing competition. Treat an
explicit "N/A" as a real value. Do NOT assume two grants compete just because they share a
country or program — they compete only when they target the same fundable scope for the
same funding period.

STEP 2 — Find the competing pipeline.
Call find_competing_grants with the resolved scope. It returns the Opportunities whose
allocations resolve to that scope, each with donor, amount (the ALLOCATED amount for this
scope, not the whole Opportunity Amount, when an allocation exists), stage, probability,
close date, owner, restriction, allocation type (Secured/Likely/Pipeline) and status, and
funding period. Present only the fields useful to the decision.

STEP 3 — Quantify and classify.
Use the summary's remaining headroom (Secured or Forecast, whichever it states — say which),
combined competing pipeline, potential excess, scenario lines, and severity classification
(No Material / Moderate / High / Critical). Present them as written.

RULES.
- Never double-count: if an Opportunity is represented through an Allocation or Gift
  Commitment, the action already reconciles it — do not re-sum.
- Never treat pipeline or likely funding as secured income; label every scenario.
- Respect funding periods and restrictions: different years or restricted purposes may not
  compete even under the same program.
- If required budget/headroom or allocation data is missing, say so and lower your
  confidence — never manufacture headroom.
- Do not expose SOQL, record IDs, match keys, or field API names unless an administrator
  asks.
- For follow-ups like "what if the Gates opportunity closes?", reuse the prior result's
  scope and opportunities and recalculate; do not restart.
- When competition is High or Critical, the summary already recommends coordinating with
  Grants Finance — present that recommendation as written.
If the conversation moves away from competing-grants analysis, transition back to the
router for reclassification.
```

## 5. Reasoning & retrieval logic

Order of operations (all read-only):

1. **Resolve scope.** Reuse `AmaizeGetOpportunityContext` (named grant → country/program/
   year via Restriction) and the Headroom Analysis identification path
   (`HeadroomService.analyze`) to pin a Budget Line, or a country+program set of lines.
2. **Gather competing allocations.** For the resolved Budget Line(s), load `Allocation__c`
   by direct `Budget_Line__c` link **and** by approved Match Key
   (`Allocation_Match_Key__c = Budget_Line_Unique_Key__c`) — reusing `AllocationSelector`.
   Walk `Allocation → Restriction → Gift_Commitment → Opportunity` for grant context.
3. **Reconcile to avoid double-counting.** Group by Opportunity. For each, prefer the
   **allocated amount** (`Funds_Allocated__c`) for this scope over the full
   `Opportunity.Amount`. Exclude `Closed Lost` and `Cancelled`/`Draft` allocations from
   "competing" demand; treat `Secured`/`Released` as already-consumed headroom, and
   `Likely`/`Pipeline` as competing pipeline.
4. **Compute exposure.** `Remaining headroom` from the Budget Line's stored
   `Secured_Headroom__c` / `Forecast_Headroom__c`. `Combined competing pipeline` = Σ of the
   competing (Likely+Pipeline) allocated amounts. `Potential excess` = combined − remaining.
5. **Scenarios.** Rank competing opportunities by stage/probability and emit cumulative
   "if A closes / if A+B / if all" remaining-headroom lines, plus a probability-weighted
   line using `Prob_Weighted_Allocation_Amount__c`.
6. **Classify severity** (see §7 guardrails for the non-mechanical rule).

## 6. Recommended response structure

`## Competing Grants Summary` → `## Program Headroom` → `## Competing Opportunities` (table)
→ `## Competition Analysis` → `## Scenario Impact` → `## Risks / Considerations` →
`## Suggested Coordination`. (Same section set the brief specifies; the action returns a
pre-composed Markdown `summary` so the agent speaks it verbatim.)

## 7. Guardrails

- Read-only; never claim to create/change/approve any record; no DML.
- Never double-count Opportunity vs Allocation vs Gift Commitment amounts.
- Never present Likely/Pipeline as Secured; always label scenarios.
- Severity is **not** derived from one number alone — it weighs stage, probability,
  allocation status (approved vs pending), restriction specificity, funding period overlap,
  existing secured funding, and donor flexibility. A single early-stage 10%-probability
  opportunity exceeding headroom is *not* Critical.
- If the Budget Scenario is not the current/designated one, say which scenario is used and
  flag that a newer plan may exist outside Salesforce.
- Prefer allocation-level data over broad Opportunity Amount; prefer the current
  `Is_Current_Scenario__c = true` scenario over combining scenarios.

## 8. Missing-data handling

- No Budget Line / headroom for the scope → say so, do not estimate.
- An opportunity in scope but with **no confirmed allocation or restriction** → include it
  as *unconfirmed*, state that competition can't be confirmed at high confidence, and do not
  fold its full Amount into the combined figure.
- Allocations `Draft`/`Suggested`/`Pending` → count separately from `Approved` and note it.
- Multiple scenarios present → name the one used.

## 9. Example user inputs

- "Do we have any grants competing for Kenya Agroforestry?"
- "Which opportunities are competing for Nigeria program headroom in FY2027?"
- "If both the Gates and Mastercard opportunities close, do we overfund Kenya Core Program?"
- "Is the Agroforestry program at risk of being overfunded?"
- "What opportunities overlap with the ABC Foundation proposal?"
- Follow-up: "What if Mastercard closes too?"

## 10. Example high-quality response

> **Competing Grants Summary**
> Three pipeline opportunities are targeting the same Kenya / Core Program – KE / FY2027
> envelope. Together they represent **$2.8M** of competing funding against **~$1.8M** of
> remaining secured headroom. If all three close at their proposed amounts, the program
> would exceed available headroom by **~$1.0M**.
>
> **Program Headroom** — Scenario: 2027 Secured Funds (current) · Kenya · Core Program – KE
> Budget $5.0M · Secured $3.2M · **Remaining secured headroom $1.8M**
>
> **Competing Opportunities**
> | Opportunity | Donor | Amount (allocated) | Stage | Prob | Close | Type |
> |---|---|---|---|---|---|---|
> | Gates – Kenya Core 27 | Gates Fdn | $1.2M | Negotiation | 75% | 2027-03 | Likely |
> | Mastercard – Kenya Core | MCF | $1.0M | Proposal | 50% | 2027-06 | Pipeline |
> | ABC – Kenya Core | ABC Fdn | $0.6M | Qualification | 30% | 2027-09 | Pipeline |
>
> **Scenario Impact**
> If Gates closes → remaining $0.6M. If Gates + Mastercard → **−$0.4M (over-allocated)**.
> If all three → **−$1.0M**. Probability-weighted competing pipeline ≈ $1.7M → ~$0.1M left.
>
> **Risks / Considerations** — Two late-stage deals alone exhaust headroom; ABC has no
> confirmed restriction yet, so its scope is unconfirmed.
>
> **Suggested Coordination** — Consider aligning with Grants Finance and the Gates/Mastercard
> RMs before advancing both at current amounts, as together they exceed remaining headroom.

## 11. Topics / actions

New invocable action **`AmaizeFindCompetingGrants`** (label: *Find Competing Grants*):

| Input | Type | Req | Notes |
|---|---|---|---|
| country | string | ✓ | matched to Budget_Line__c.Country__c |
| businessUnit | string | ✓ | suffix-tolerant (Core Program ↔ Core Program – KE) |
| fiscalYear | integer | – | |
| subUnit / department / costType / costCategory | string | – | narrow to one Budget Line; N/A honored |

Outputs: `summary` (composed Markdown), `severity`, `combinedPipeline`, `remainingHeadroom`,
`resultsJson`, `found`. Also reuse **`AmaizeGetOpportunityContext`** (named-grant scope) and
the Headroom Analysis actions for scope resolution.

## 12. Objects & fields to retrieve

- **Budget_Line__c** — the 7 dimensions, `Budget_Amount__c`, `Secured/Likely/Pipeline_Funding__c`,
  `Forecast_Funding__c`, `Secured_Headroom__c`, `Forecast_Headroom__c`, `Headroom_status__c`,
  `Budget_Line_Unique_Key__c`, `Budget_Scenario__r.Is_Current_Scenario__c/Fiscal_Year__c/Scenario_Type__c`.
- **Allocation__c** — `Budget_Line__c`, `Funds_Allocated__c`, `Allocation_Type__c`
  (Secured/Likely/Pipeline), `Allocation_Status__c` (Draft/Suggested/Approved/Released/Cancelled),
  `Prob_Weighted_Allocation_Amount__c`, `Allocation_Match_Key__c`, `Restriction__c`.
- **Restriction__c** — `Restriction_Country__c`, `Business_Unit__c`, `Sub_Unit__c`,
  `Cost_Type__c`, `Department_Name__c`, `Cost_Category__c`, `Gift_Commitment__c`.
- **GiftCommitment** — `OpportunityId`, `DonorId`, `Status`.
- **Opportunity** — `Name`, `Amount`, `Probability`, `StageName`, `CloseDate`, `Guardian__c`
  (the owning RM). *Do not source country/program from the Opportunity.*

## 13. How it uses each object

`Budget Scenario` scopes to the current/designated plan → `Budget Line` gives the headroom
figures for the scope → `Funding Allocation` (Allocation__c) links real committed/pipeline
money to that line (direct link or Match Key) → each allocation's `Restriction` gives the
true country/program/purpose → `Gift Commitment` bridges to the `Opportunity` for donor,
stage, probability, close date, and owning RM. Competition is measured at the
**allocation-to-Budget-Line** grain, which is what prevents double-counting and false
competition.

## 14. Router invocation

Route to **Competing Grants Analysis** when the user's intent is *comparative/overlap*:
"competing", "compete for", "overlap", "both/all … close", "overfund/over-allocated",
"multiple opportunities/donors targeting the same …", "combined pipeline", "at risk of
overfunding". Route to **Headroom Analysis** for single-scope "how much headroom" questions.
When ambiguous, resolve scope first (Headroom Analysis) then offer the competition view.

## 15. Recommended improvements

1. **Reuse, don't rebuild.** Implement `AmaizeFindCompetingGrants` on top of the existing
   `HeadroomService` + `AllocationSelector` (extend it with an "all allocations, grouped by
   Opportunity" query). The Budget-Line-first engine and Match Key logic are already built,
   tested, and deployed.
2. **Model competition at the Budget Line grain, not country/program.** This is the single
   biggest correctness win and directly satisfies the brief's "don't assume competition"
   rule — two Kenya/Core Program grants on different cost categories only compete if they hit
   the same line (or the same rolled-up scope the user asked about).
3. **Use `Allocation_Status__c` + `Allocation_Type__c` together** to separate consumed
   (Secured/Approved) from competing (Likely/Pipeline) and from unconfirmed (Draft/Suggested).
4. **Prefer `Prob_Weighted_Allocation_Amount__c`** for the probability-weighted scenario —
   it already exists as a formula, so the agent stays grounded.
5. **Consider a Budget-Scenario-type awareness** (`Secured Funds` vs `Forecast Scenario`) so
   the agent can state which planning lens it is answering under.
6. **Guardrail parity** with Headroom Analysis: same read-only, no-hallucination, verbatim-
   summary discipline, so the two sub-agents behave consistently.
