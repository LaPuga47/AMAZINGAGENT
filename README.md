# A-maize-ing Headroom Assistant

An internal **Agentforce** agent for One Acre Fund that answers grant **funding-headroom**
questions for Fundraising Relationship Managers and Grants Finance staff. It is
**read-only** and every figure it states is grounded in the org's own
`Budget_Scenario__c` / `Budget_Line__c` / `Allocation__c` data — it never paraphrases,
recomputes, or invents numbers.

## Headroom Analysis architecture

The current agent version (**v18**) routes questions to three read-only sub-agents —
**Headroom Analysis** (single-scope headroom), **Competing Grants Analysis** (competition +
funding lineage), and the router's off-topic/ambiguous fallbacks. All are **Budget-Line-first**:
the Budget Line is the authoritative source; allocations and lineage hang off it.

### Governed Headroom aggregation

`analyze_headroom` resolves a **Headroom category/program** to its governed Budget Line
population, then **SUMs** the financial fields across **all** qualifying lines for the given
country and fiscal year — it never picks one line, averages, or recalculates the stored
headroom fields. `HeadroomCategoryResolver` is the single source of truth for the mapping:

| Category (synonyms) | Business Unit base | Department filter | Notes |
|---|---|---|---|
| **Core Program** (Core Field Program, Field Program) | `Core Program` | — | HR-001 |
| **Rural Retail** (RRT) | `Farm Input Sales` | `Rural Retail` | HR-002 |
| **Market Access** (MKT) | `Farm Input Sales` | `Market Access` | HR-003 |
| **Trees** (TRE) | `Farm Input Sales` | `Trees` | HR-004 |
| **System Change Extension & Other Programs** | `Systems Change` | — | HR-005 |
| **Unrestricted** | — | — | HR-006 — governed **zero**, status *Not Applicable* |
| **Working Capital** | — | — | HR-007 — governed **zero**, status *Not Applicable* |
| Other Support Departments, Miscellaneous | — | — | **Not configured** — the agent says so, never guesses |

Resolution rules:
- **Country** is the authoritative filter; business units are matched **suffix-tolerant** on
  the base name (`Core Program` matches the org's `Core Program - KE`), never by parsing the
  suffix. Fiscal Year filters explicitly and defaults to the current scenario when omitted.
- An explicit `N/A` is a **real value**, not missing data.
- Aggregation is scoped to the **current Budget Scenario**, so materially different scenarios
  are never silently combined; the scenario used is reported.
- **No qualifying lines is reported as such — never as a financial value of zero.** Unknown
  categories fall back to a direct business-unit match (a literal filter, not a guessed mapping).
- The historical spreadsheet rules are **not** recreated (e.g. Systems Change is not reduced by
  Rural Retail / Market Access / Trees — the org's Business Unit + Department mapping already
  separates them).

Every successful aggregation returns the **eight governed fields** — Budget Amount, Secured /
Likely / Pipeline / Forecast Funding, Secured / Forecast Headroom, Headroom Status — plus the
**number of Budget Lines included** and a short interpretation. Headroom Status is *derived*
from the summed Secured Headroom (a status is never summed).

### Conversational single-program answers

For a simple question like *"Should I raise money for Kenya Trees in 2027?"* the action returns
**two renderings** and the agent shows the conversational one by default — **full financial
intelligence underneath, a simple business answer on top**:
- **`summary`** (default): a 2–4 sentence business answer that leads with the fundraising
  position and ends with a contextual follow-up, e.g. *"There appears to be room for additional
  fundraising for Kenya Trees in FY2027, with approximately $473K of available Headroom. Around
  $27K is currently secured, with no likely or pipeline funding mapped."* The agent may open a
  yes/no question with a verdict (**Yes.** / **Not based on the current Headroom position.** /
  **There is limited room.**) that must agree with the governed result.
- **`detail`** (on demand): the full field-by-field breakdown — shown only when the user asks
  for the numbers, a breakdown, how it was calculated, secured-vs-forecast, pipeline/likely
  detail, or the Budget Lines.

Presentation rules (no change to the governed calculation):
- **Secured vs Forecast Headroom** are shown together only when they differ materially (i.e.
  likely + pipeline funding is material); otherwise a single *available Headroom* figure.
- **Funding categories** that are zero aren't listed — *"…with no likely or pipeline funding
  mapped"* instead of four `$0` lines.
- **Negative** → *"does not currently show available Headroom … beyond its governed funding
  capacity"*; **zero** → *"fully funded … no additional governed Headroom"*; never labelled a
  funding gap or available Headroom.
- **Natural names** (*Kenya Trees*), never internal Business Units.
- **Budget Scenario** metadata is kept internal; a short note appears only on a year mismatch.
- Accepting the follow-up (*"show me the grants"*) hands off to **Competing Grants Analysis**
  on the **same** resolved Country + Fiscal Year + Headroom Category — never a new population.

### Multi-country comparison

`compare_headroom` (`AmaizeCompareHeadroom`) answers "what's the funding gap in **one program**
across **several countries** in FY2027?" without repeating a full financial block per country.
It resolves **each country independently through the same `HeadroomService.aggregate`** the
single-country query uses — so a compared figure always matches a direct query — then renders
one concise block:
- a lead interpretation stating the metric (**Forecast Headroom**) once,
- **one compact line per country**: `Country: Available Headroom $X | Secured $Y | Pipeline $Z`, and
- a group summary naming the country with the most available Headroom.

Sign interpretation (see [Headroom calculation](#headroom-calculation-source-of-truth)):
**positive Forecast Headroom → `Available Headroom $X`** (room to raise more); **negative →
`Overfunded $X`** (funding exceeds capacity); zero → *Fully funded*. Magnitudes are always
shown positive, and negative Headroom is never called a funding gap or available Headroom. A country with no qualifying lines reads **"No qualifying Budget Line records
found"**, never `$0`. With more than eight countries it shows the **eight largest gaps** and
says so. Full single-country detail is one drill-down away via `analyze_headroom`.

### Concise competing-grants view

`find_competing_grants` (`AmaizeFindCompetingGrants`) answers *"do we have competing grants for
Kenya Trees in 2027?"* with a short fundraising view by default, and the full analysis on
demand — same two-rendering pattern as `analyze_headroom`:
- **`summary`** (default): the grants already contributing **secured** funding, the **pipeline /
  likely** Opportunities that could use the rest (each as *contribution | probability | stage*
  with a clickable Opportunity + Restriction link), and a one-line Headroom conclusion.
- **`detail`** (on demand): Risk & Confidence, Why They Compete, the full Headroom breakdown,
  What-Can-Fit, Minimum Adjustment, coverage, timing, Data Quality.

**Competition is classified correctly**: **0** relevant pipeline/likely Opportunities → *"no
competing grants"*; **1** → *"one Opportunity … not yet a competing-grants situation"* (a single
Opportunity is never called "competing"); **2+** → competing, with combined contribution vs
available Headroom. The default view omits total Opportunity Amount and allocation coverage (the
relevant figure is each grant's **contribution to this program**); those surface on drill-down,
or automatically when analysis confidence is not High. Clickable **Opportunity** and
**Restriction** links are always shown; Gift Commitment / Allocation links are drill-down only.

All user-facing responses follow a shared **response style**: the year is written directly (no
"FY"), no implementation terms ("governed" / "mapped" / "linked" / "exposure") reach the user,
record links show the human-readable name, and the answer precedes a single follow-up prompt.
The internal calculations, field names, and precision are unchanged.

### Allocation drill-down

`get_allocations` (`AmaizeGetAllocations`) answers *"show me the full list of allocations behind
Kenya Trees FY2027"* — an explicit **intent switch**: it retrieves and displays the individual
Funding Allocation records instead of re-offering them. It **reuses `CompetingGrantsService.analyze`**
(the same governed Budget Line population and allocations as the competing-grants view, so totals
reconcile) and renders:
- a lead count/total (*"N Funding Allocation records across M Opportunities, with $X mapped…"*),
- **grouped by Opportunity**, split into **SECURED** vs **LIKELY / PIPELINE** sections, with a
  per-Opportunity exposure total that reconciles to its shown allocations,
- per allocation: *[FA name] — $amt | Type | Status*, with clickable **Allocation, Opportunity,
  Restriction, Gift Commitment (or "Not linked"), and Budget Line** links (all URLs built
  server-side; the LLM never constructs them),
- optional `allocationType` / `allocationStatus` / `opportunityName` filters, and `startIndex`
  paging that shows the first 15 and says how many remain (never silent truncation).

### Allocation matching (priority order)

1. **Direct** `Allocation__c.Budget_Line__c` lookup.
2. **Approved Match Key** — `Allocation_Match_Key__c = Budget_Line_Unique_Key__c` (the
   `Allocation - Budget Line Linking` flow's mechanism; not reinvented in Apex).
3. Otherwise, clarify rather than make a weak match.

Allocations are summed by `Allocation_Type__c` (**Secured / Likely / Pipeline**), which is
set by the `Automatically Classify Allocation Type by Probability` flow.

### Headroom calculation (source of truth)

Figures are read from the Budget Line's **stored/calculated fields**, so the agent can
never disagree with the org's own formulas:

| Concept | Field / formula |
|---|---|
| Budget (cost) | `-Budget_Amount__c` (stored negative as an expense) |
| Secured Headroom | `Secured_Headroom__c` = `-Budget_Amount__c - Secured_Funding__c` |
| Forecast Headroom | `Forecast_Headroom__c` = `-Budget_Amount__c - (Secured + Likely + Pipeline)` |
| Status | `Headroom_status__c` (≥250K → Available; ≥0 → Some; else → Unavailable) |

Negative headroom is valid and is explained as **over-allocation**, not an error.

### Apex layering

Thin invocable actions over a selector → service → DTO stack (all `with sharing`,
`USER_MODE`, no DML in the read path):

- **Actions:** `AmaizeAnalyzeHeadroom` (governed category aggregation), `AmaizeCompareHeadroom`
  (concise multi-country comparison for one program), `AmaizeRankHeadroom` (portfolio),
  `AmaizeFindCompetingGrants` + `AmaizeGetFundingContext` (competing grants & funding lineage).
  Category rules live in `HeadroomCategoryResolver`; aggregation in
  `HeadroomService.aggregate` + `BudgetLineSelector.aggregateScope`.
- **Service/DTOs:** `HeadroomService`, `HeadroomAnalysis`, `BudgetLineDimensions`,
  `AllocationBreakdown`, `HeadroomKeyBuilder`, `HeadroomFormat`, `AmaizeFormat`.
- **Selectors:** `BudgetLineSelector` / `IBudgetLineSelector`,
  `AllocationSelector` / `IAllocationSelector`.
- **Shared calc:** `AmaizeBudgetHeadroom` mirrors the org's Budget Line formulas exactly.

### Agent bundle

- **Authoring source (the one file you edit):**
  `aiAuthoringBundles/A_maize_ing_Headroom/A_maize_ing_Headroom.agent` — the Agent Script
  that declares every subagent, its actions, and the router.
- **Compiled/deployed (generated — do not hand-edit):**
  `genAiPlannerBundles/A_maize_ing_Headroom_v<N>/` (planner bundle, agent graph, per-action
  schemas) + `bots/A_maize_ing_Headroom/v<N>.botVersion-meta.xml`. Each activation is a new
  version `v<N>`; the current live version is **v18**, with subagents
  `agent_router → { competing_grants, headroom_analysis, off_topic, ambiguous_question }`.
- The router classifies on **primary intent**: *"is there fundraising capacity?"* →
  **Headroom Analysis** (this includes decision-framed questions like *"should I raise money
  for Kenya Trees in 2027?"*, funding-gap, room-to-raise, and over-allocation of one scope —
  even when pipeline opportunities exist); *"which grants may consume that capacity?"* →
  **Competing Grants Analysis** (competing/pipeline opportunities, allocations, restrictions,
  donors, "if these close", overfunding risk, funding lineage, portfolio collision risk).
  Headroom Analysis offers a follow-up handoff into competing grants on the same resolved
  scope. Off-topic and ambiguous requests fall through to their own topics.

### Changing the agent — use `sf agent publish` (not a hand-built deploy)

The `genAiPlannerBundle` / `agentGraph` is a **compiler output**. Do not author or
`sf project deploy` it by hand — the server rejects inconsistent bundles, and a new version
of an active agent can't be added by a raw metadata deploy anyway. Instead, edit the
authoring `.agent` and let the platform compile and version it:

```bash
# 1. Edit the Agent Script
#    aiAuthoringBundles/A_maize_ing_Headroom/A_maize_ing_Headroom.agent

# 2. Validate it compiles
sf agent validate authoring-bundle --api-name A_maize_ing_Headroom --target-org <alias>

# 3. Publish — compiles server-side and creates a NEW version (e.g. v5),
#    retrieving the generated genAiPlannerBundle + botVersion back into the project
sf agent publish authoring-bundle --api-name A_maize_ing_Headroom --target-org <alias>

# 4. Activate the new version (only one version is active at a time)
sf agent activate --api-name A_maize_ing_Headroom --version <N> --target-org <alias>
```

Notes:
- To add/replace a version while the agent is already active, the platform requires it to be
  inactive first: `sf agent deactivate --api-name A_maize_ing_Headroom` (a re-activate then
  deactivate normalizes the state if `deactivate` reports "no active version"). `publish`
  followed by `activate` is the normal flow; `activate` auto-supersedes the prior version.
- Deploy the **Apex actions first** (below) so `publish` can bind the new topic's actions.
- `sf agent preview` needs an interactive TTY; for headless checks, call the invocable
  actions via `sf apex run` (they are the exact code the live agent invokes).

### Build, test, deploy (Apex)

```bash
# Run the Apex tests
sf apex run test --tests HeadroomKeyBuilderTest BudgetLineSelectorTest \
  AllocationSelectorTest HeadroomServiceTest AmaizeAnalyzeHeadroomTest \
  AmaizeRankHeadroomTest CompetingGrantsServiceTest AmaizeFindCompetingGrantsTest \
  FundingContextServiceTest AmaizeGetFundingContextTest \
  --result-format human --target-org <alias>

# Deploy the Apex
sf project deploy start --source-dir force-app/main/default/classes \
  --test-level RunSpecifiedTests --target-org <alias>
```

### Testing the agent — required user access

The agent's actions run in **user mode** (`with sharing` + `AccessLevel.USER_MODE`), so each
user only sees what their permissions allow. If one tester gets grounded answers and another
gets "not found" / empty results or the agent doesn't respond, it is almost always an access
gap, not a bug. A user testing the agent needs **all** of:

1. **The agent's permission sets** — assign the sets that grant the object Read and
   field-level security the agent queries. In this org those are
   **`Amaize_Grant_Assistant_Admin`** (Budget Scenario/Line objects + `Opportunity.Guardian__c`
   FLS), **`OAF_Agent_ReadOnly`** (Restriction / Gift Commitment / Opportunity / Account read),
   and **`Fundraising_User`**, plus **`Agentforce_Employee_Agent`**. A missing field grant
   surfaces at runtime as a confusing `System.QueryException: No such column 'X'` (user mode
   hides fields the user can't read) — e.g. `No such column 'Guardian__c' on entity
   'Opportunity'` means the user lacks FLS on `Guardian__c`, granted by
   `Amaize_Grant_Assistant_Admin`. Note the **System Administrator profile does not grant
   custom-field FLS**, so admins need these sets too.
2. **Agentforce Coworker permission-set _license_** — `AISearchUserPsl`. This is **required to
   run an Employee Agent and is NOT granted by the System Administrator profile** — it is a
   seat-based license assigned per user. This is the most common cause of "my tests pass but
   my colleague's fail": the colleague has the permission set but not the license.

   ```bash
   sf org assign permsetlicense --name AISearchUserPsl \
     --on-behalf-of <username> --target-org <alias>
   ```
3. **Data access** to the funding objects — `Budget_Scenario__c`, `Budget_Line__c`,
   `Allocation__c`, `Restriction__c`, `GiftCommitment`, `Opportunity`. Internal org-wide
   defaults are open (ReadWrite / ControlledByParent), and `GiftCommitment` access comes via
   the **Fundraising Access** license, so ensure testers have that too.

After assigning a license, the user must **log out and back in** for it to take effect. Verify
with:

```bash
sf data query --target-org <alias> --query "SELECT PermissionSetLicense.MasterLabel \
  FROM PermissionSetLicenseAssign WHERE Assignee.Username='<username>'"
```

> Tip: bundle the `Agentforce_Employee_Agent` permission set + the Agentforce Coworker license
> (+ Fundraising Access) into your tester onboarding / a permission-set group so every tester
> gets identical access.

---

## Developing with Salesforce DX

Salesforce DX is a development approach that brings source-driven development, team collaboration, and continuous integration to the Salesforce Platform. Instead of working directly in an org through a web browser, you work with metadata as source files in a local DX project, track changes in version control, and deploy through automated processes.

This project template gets you started with the tools and structure you need to build Salesforce applications using source control, scratch orgs, and the Salesforce CLI.

## Prerequisites

Before you start, make sure you have:

- **Salesforce CLI** - Download from [developer.salesforce.com/tools/salesforcecli](https://developer.salesforce.com/tools/salesforcecli). See [Install Salesforce CLI](https://developer.salesforce.com/docs/atlas.en-us.sfdx_setup.meta/sfdx_setup/sfdx_setup_install_cli.htm) for details.
- **VS Code with Salesforce Extension Pack** - See [Installation Instructions](https://developer.salesforce.com/docs/platform/sfvscode-extensions/guide/install.html) for details. Includes the Agentforce Vibes extension.
- **A development org** - Sign up for a free Developer Edition org [here](https://developer.salesforce.com/signup).
- **Dev Hub enabled** (optional, required to create scratch orgs) - You can enable Dev Hub in your development org under Setup > Dev Hub.  See [Provide Developers Access to Salesforce DX Tools](https://developer.salesforce.com/docs/atlas.en-us.sfdx_dev.meta/sfdx_dev/sfdx_setup_dx_tools.htm).

## Project Structure

Your DX project follows this structure:

- **`force-app/main/default/`** - Your metadata source files live in this default package directory. You can configure additional package directories in the `sfdx-project.json` file.
- **`config/`** - Scratch org definitions and project settings
- **`scripts/`** - Automation scripts for common tasks
- **`sfdx-project.json`** - Project manifest that defines package directories, namespace, API version, and other project-level settings

See [Salesforce DX Project Configuration](https://developer.salesforce.com/docs/atlas.en-us.sfdx_dev.meta/sfdx_dev/sfdx_dev_ws_config.htm).

## Get Started

Ready to start developing? The [Get Started with Salesforce DX](https://developer.salesforce.com/docs/atlas.en-us.sfdx_dev.meta/sfdx_dev/sfdx_dev_get_started_dx.htm) guide walks you through your first project, from creating a scratch org to creating a simple Apex class or LWC to deploying your code to a sandbox.

## Common Salesforce CLI Commands

Here are common CLI commands that you'll use the most:

- `sf org login web`: Authorize an org
- `sf org open`: Open your org in a browser
- `sf org create scratch`: Create a scratch org
- `sf project deploy start`: Deploy metadata to your org
- `sf project retrieve start`: Retrieve metadata from your org
- `sf template generate <artifact>`: Scaffold new components, such as Apex classes and triggers, LWC components, Lightning apps, and more
- `sf apex <command>`: Run Apex tests, run anonymous Apex blocks, and view logs
- `sf data <command>`: Work with test data
- `sf alias <command>`: Manage org aliases
- `sf config <command>`: Configure CLI settings

## Use Agentforce Vibes to Build Lightning Apps

Transform your ideas into custom Lightning apps that extend CRM workflows directly in Lightning Experience. Through natural conversations with Agentforce Vibes, implement custom objects and fields, complex business logic, and dynamic UI components. See [Build a Lightning App Using Agentforce Vibes](https://developer.salesforce.com/docs/platform/einstein-for-devs/guide/lexapp-overview.html).

## Additional Resources

- [Agentforce Vibes Developer Guide](https://developer.salesforce.com/docs/platform/einstein-for-devs/guide/einstein-overview.html)
- [Salesforce CLI Installation Guide](https://developer.salesforce.com/docs/atlas.en-us.sfdx_setup.meta/sfdx_setup/sfdx_setup_intro.htm)
- [Salesforce DX Developer Guide](https://developer.salesforce.com/docs/atlas.en-us.sfdx_dev.meta/sfdx_dev/)
- [Salesforce CLI Command Reference](https://developer.salesforce.com/docs/atlas.en-us.sfdx_cli_reference.meta/sfdx_cli_reference/)
- [Salesforce CLI Plugin Development Guide](https://developer.salesforce.com/docs/platform/salesforce-cli-plugin/guide/conceptual-overview.html)
- [Salesforce VS Code Extensions Documentation](https://developer.salesforce.com/tools/vscode/)

