# Onboarding — A-maize-ing Headroom Assistant

Welcome. This is the **fast-start** guide for developers joining the A-maize-ing Headroom
Assistant. It covers the mental model, the two dev loops, and the non-obvious gotchas.
For the deep architecture reference, read [`README.md`](./README.md) after this.

---

## 1. What this is

A **Salesforce Agentforce Employee Agent** for One Acre Fund that answers grant
**funding-headroom** and **competing-grants** questions for Fundraising Relationship
Managers (RMs) and Grants Finance staff.

- **Read-only.** The agent never creates, changes, or deletes records. No DML in the read path.
- **Grounded in data.** Every figure comes from the org's own Budget Line / Allocation records —
  the agent never invents, rounds, or recomputes numbers.
- **Current live version: `v29`** (agents are versioned; one version is active at a time).

The agent has a **router** and four sub-agents:
`agent_router → { headroom_analysis, competing_grants, off_topic, ambiguous_question }`.
The router picks by **primary intent**: *"is there fundraising capacity?"* → **Headroom Analysis**;
*"which grants may consume it?"* → **Competing Grants Analysis**.

---

## 2. One-time setup

```bash
# Salesforce CLI (sf), Node, and Git required. Then authorize the sandbox:
sf org login web --alias headroom --instance-url https://test.salesforce.com
sf config set target-org headroom          # so you can omit --target-org

git clone <this repo> && cd Amaizeing-Headroom-Assistant
```

**To use/test the agent as a user**, your Salesforce user needs BOTH:
1. the **`Agentforce_Employee_Agent`** permission set (agent + FLS), and
2. the **`AISearchUserPsl`** (Agentforce Coworker) permission-set **license** — *not* granted by
   the System Administrator profile, so assign it explicitly.

Missing FLS shows up in user-mode Apex as `System.QueryException: No such column 'X'`.
See the README "Testing the agent — required user access" section for the full list.

---

## 3. The mental model (read this before touching code)

### Budget-Line-first
The **Budget Line** (`Budget_Line__c`) is the authoritative record. Allocations, restrictions,
opportunities, and donors all hang off it. Headroom is a **sum of stored Budget Line fields** for
a scope — never recomputed in Apex.

### A "scope" = Category + Country + Fiscal Year
`HeadroomCategoryResolver` maps a program name (e.g. *Trees*, *Core Program*, *Rural Retail*) to a
Budget Line filter (business-unit base + optional department), rules **HR-001…HR-007**. Country is
the authoritative filter; business units match **suffix-tolerant** (`Core Program` matches
`Core Program - KE`). This resolver is the single source of truth — never hard-code the mapping.

### Headroom sign convention (get this right)
`Forecast_Headroom__c = -Budget_Amount__c - (Secured + Likely + Pipeline)` (budget is stored
negative). So by sign:

| Sign | Meaning | User-facing wording |
|---|---|---|
| **positive** | budget not yet fully funded | **"available Headroom"** (room to raise more) |
| **zero** | fully funded | **"fully funded"** |
| **negative** | funding exceeds budget | **"Overfunded by $X"** |

Never call negative Headroom a "funding gap" or "available Headroom". Interpret **Secured** and
**Forecast** Headroom separately.

### Program Mode vs Dimension Mode (one shared resolver)
A scope isn't always a standard program. Users also ask about an explicit **Budget Line
dimension** — a Cost Category / Department / Cost Type / Sub-Unit such as *Crop Insurance* or
*Staff Costs* ("grants funding Crop Insurance in Malawi in 2027"). **`BudgetLineScopeResolver`**
is the single shared resolver that turns any request into a qualifying Budget Line filter and
returns one of three modes: **PROGRAM**, **DIMENSION** (auto-detects the value's dimension; asks
if it's `AMBIGUOUS` across dimensions, reports `NOT_FOUND` if in none — never guesses), or
**PROGRAM_PLUS_DIMENSION**. Both `HeadroomService.aggregateExplicit` and
`CompetingGrantsService.analyzeExplicit` consume it, so a dimension resolves to the *same* lines
in either sub-agent. Users never type field API names — resolve business terms, don't require
`Cost Category = …`.

### Next-available-year guidance
When a single-year Program question has **no available Headroom** (fully funded / overfunded),
`HeadroomService.findNextAvailableYear` looks forward — reusing `aggregate()` per year over only
the years that have data — to the earliest future year with room, and the answer leads the user
there. It **never invents a year**: if none qualifies it reports the searched span and offers
other countries / programs. An explicit multi-year *range* suppresses this per-year lookahead
(the `partOfRange` action input) so the agent composes a year-by-year answer instead.

### Consistency guarantee
Headroom Analysis and Competing Grants resolve the **identical** Budget Line population for the
same scope, so their figures always agree. There's an automated test enforcing this — keep it green.

---

## 4. Apex architecture

Thin **invocable action → service → selector → DTO** layering. All `with sharing`,
`AccessLevel.USER_MODE`, no DML in the read path.

- **Actions** (what the agent calls): `AmaizeAnalyzeHeadroom` (single scope), `AmaizeCompareHeadroom`
  (multi-country), `AmaizeRankHeadroom` (portfolio), `AmaizeFindCompetingGrants`,
  `AmaizeGetAllocations` (allocation drill-down), `AmaizeGetFundingContext` (lineage),
  `AmaizeOpportunityCompetition`, `AmaizePortfolioRisks`, `AmaizeGetOpportunityContext`.
- **Services / DTOs:** `HeadroomService` + `HeadroomAggregate`, `CompetingGrantsService` +
  `CompetingGrantsResult` / `CompetingGrant`, `PortfolioHeadroomService`, `FundingContextService`.
- **Selectors:** `BudgetLineSelector`, `AllocationSelector` (all SOQL lives here).
- **Shared helpers:** `HeadroomCategoryResolver` (HR rules), `BudgetLineScopeResolver` (Program /
  Dimension / Program+Dimension → qualifying Budget Line filter, consumed by both sub-agents),
  `AmaizeBudgetHeadroom` (mirrors the org's Budget Line formulas), `AmaizeFormat` (money → `$1.2M`),
  `AmaizeLink` (server-side record URLs — the LLM must **never** build URLs).

> **User-facing text is composed in Apex**, in each action's `summary`/`detail` fields — not just in
> the prompt. To change what the user reads, edit the composer strings (deterministic) *and* the
> agent instructions, then redeploy + republish.

Note: `AmaizeCheckHeadroom`, `AmaizeFindPrograms`, and the grant-schedule classes are **legacy /
not wired into the live agent** — don't extend them without checking they're actually referenced.

---

## 5. Dev loop A — Apex

```bash
# Deploy classes. In this SANDBOX, running specified tests on a partial deploy triggers a
# 75%-coverage GATE that can fail the deploy even when tests pass. Two-step it:
sf project deploy start --source-dir force-app/main/default/classes --test-level NoTestRun
sf apex run test --tests AmaizeAnalyzeHeadroomTest --tests AmaizeFindCompetingGrantsTest \
  --tests AmaizeCompareHeadroomTest --result-format human --wait 30
```

Test data lives in `HeadroomTestData` (factory) — it builds the full
Account → GiftCommitment → Restriction → Allocation chain. **Respect the org automations** it
works around (see §7).

---

## 6. Dev loop B — the agent (never hand-edit the compiled bundle)

The **only** file you edit for agent behavior is the Agent Script:
`force-app/main/default/aiAuthoringBundles/A_maize_ing_Headroom/A_maize_ing_Headroom.agent`

The `genAiPlannerBundles/…` and `bots/…` folders are **compiler output** — do not hand-author or
`sf project deploy` them; the server rejects inconsistent bundles.

```bash
# 1. Edit the .agent file (instructions, action wiring, routing).
# 2. Publish — compiles server-side, creates a NEW version, pulls the generated bundle back:
SFDX_DISABLE_DNS_CHECK=true sf agent publish authoring-bundle --api-name A_maize_ing_Headroom
# 3. Activate that version (only one is active at a time):
sf agent activate --api-name A_maize_ing_Headroom --version <N>
```

Find `<N>`: `ls -dt force-app/main/default/genAiPlannerBundles/A_maize_ing_Headroom_v*` (newest).
Publishing can take ~40–60s and occasionally DNS-times-out — the `SFDX_DISABLE_DNS_CHECK=true`
prefix and a retry fix it. Long publishes are best run in the background.

### Smoke-test an action live
You can't drive the Agentforce chat/preview headlessly (`sf agent preview` needs a TTY). Instead
call the action from anonymous Apex to see the exact `summary` a user would get:

```apex
AmaizeAnalyzeHeadroom.Request r = new AmaizeAnalyzeHeadroom.Request();
r.program = 'Trees'; r.country = 'Kenya'; r.fiscalYear = 2027;
System.debug(AmaizeAnalyzeHeadroom.analyze(new List<AmaizeAnalyzeHeadroom.Request>{ r })[0].summary);
```

### Routing regression eval (Testing Center)
Routing is decided by the deployed LLM planner, so verify it with the eval, not Apex:

```bash
sf agent test run --api-name Headroom_Routing_Eval --wait 10
```

It asserts capacity questions → Headroom Analysis and competing/opportunity questions →
Competing Grants (spec in `specs/A_maize_ing_Headroom-routing-eval.yaml`). The CLI may print
"Fail" for the `topic_sequence_match` scorer even when the `topicName` is correct — check the
actual routed topic in the JSON (`--json`) rather than the pass/fail column. In particular, a
multi-turn case shows the whole expected *sequence* against each single turn, so each turn looks
"failed" even when the sequence is right.

Companion specs in `specs/`: `…-dimension-eval.yaml` (explicit dimension like Crop Insurance
routes to both sub-agents) and `…-nextyear-eval.yaml` (no-Headroom next-available-year guidance).
To inspect an action's actual reply text end-to-end (not just routing), read the
`agentResponse.runs[].messages` from the `--json` output.

---

## 7. Gotchas that will bite you

- **Org flows rewrite your test data.** "Allocation - Budget Line Linking" re-links allocations by
  Match Key; "Classify Allocation Type by Probability" sets `Allocation_Type__c` from the
  Opportunity probability (100→Secured, 50–99→Likely, <50→Pipeline); "Opportunity After Save"
  rewrites `Opportunity.Name`; a rollup recalculates Budget Line funding when allocations attach.
  Set data via the **factory** and assert on structure, not on values the flows may change.
- **Restricted picklists.** `Budget_Line__c.Country__c`, `.BusinessUnit__c`, and `.Cost_Category__c`
  are restricted — invalid values throw `INVALID_OR_NULL_FOR_RESTRICTED_PICKLIST`. Valid countries:
  Burundi, Kenya, Malawi, Nigeria, Rwanda, Tanzania, Uganda, Zambia. `Core Program` (base, no suffix)
  is valid. `Crop Insurance` is a valid `Cost_Category__c`; `Bad Debt Expense` exists in **both**
  `Cost_Category__c` and `Cost_Type__c` (handy for exercising the resolver's ambiguity path).
  Verify field API names against the object before writing SOQL — never guess them.
- **Scenario type.** Current scenarios use `Scenario_Type__c = 'Forecast Scenario'` /
  `'Secured Funds'` — not `'Final Budget'` (a past bug).
- **Money is rounded to K/M** for display, so per-line values won't always visually sum to a total.
  It's display rounding, not a data error.
- **Response style is enforced** (system instructions + Apex): the year directly (**no "FY"**), no
  `governed` / `mapped` / `linked` / `exposure` in user text, human-readable clickable record names
  (never raw URLs), bold Markdown section headings, and a blank line before a single follow-up.

---

## 8. Git & release workflow

- Work on a **branch**; open a PR to `main` (this repo uses PR merges).
- **`sf agent publish` deploys to the org immediately** — so the live agent can get ahead of `main`
  until your PR merges. Keep the branch and the org in sync.
- **Hard-won lesson:** always **verify the merge actually landed on `origin/main` before deleting a
  branch** (`git merge-base --is-ancestor <branch> origin/main`). `git branch -d` only checks the
  branch's own upstream, not `main` — deleting too early has stranded merged-looking commits before.
- Commit trailer: `Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>`.

---

## 9. Where to look

| I want to… | Go to |
|---|---|
| Change agent behavior / routing / wording | the `.agent` file, then publish + activate |
| Change what an action returns | the matching `Amaize*.cls` action + its service |
| Change the Category → Budget Line mapping | `HeadroomCategoryResolver` |
| Change how an explicit dimension (Crop Insurance) resolves | `BudgetLineScopeResolver` |
| Adjust the no-Headroom next-year lookahead | `HeadroomService.findNextAvailableYear` + `AmaizeAnalyzeHeadroom` |
| Understand the Headroom math | `AmaizeBudgetHeadroom` + README "Headroom calculation" |
| Add/adjust SOQL | `BudgetLineSelector` / `AllocationSelector` |
| Deep architecture & data model | `README.md` |
| Verify routing / behavior | `specs/*-eval.yaml` via Testing Center (`sf agent test run`) |
