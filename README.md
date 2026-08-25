# A-maize-ing Headroom Assistant

An internal **Agentforce** agent for One Acre Fund that answers grant **funding-headroom**
questions for Fundraising Relationship Managers and Grants Finance staff. It is
**read-only** and every figure it states is grounded in the org's own
`Budget_Scenario__c` / `Budget_Line__c` / `Allocation__c` data — it never paraphrases,
recomputes, or invents numbers.

## Headroom Analysis architecture

The current agent version (**v2**) routes headroom questions to a dedicated
**Headroom Analysis** subagent that follows a strict **Budget-Line-first** sequence:

1. Interpret the request and normalize the supplied dimensions.
2. Identify the intended **Budget Line** (never start from allocations).
3. Confirm the Budget Line is specific enough — otherwise ask, don't guess.
4. Retrieve the allocations for *that* Budget Line (direct link first, then Match Key).
5. Read headroom from the Budget Line's own stored/calculated fields.
6. Return a grounded, decision-ready answer.

### Budget Line identification

A Budget Line is identified by seven dimensions:
**Fiscal Year, Country, Business Unit, Sub-Unit, Department, Cost Type, Cost Category.**

- An explicit `N/A` is treated as a **real value**, not as missing data.
- Minimum useful input is Fiscal Year + Country + Business Unit (+ Sub-Unit when it exists).
- When all seven are supplied, an **exact composite-key** lookup is used
  (`HeadroomKeyBuilder` reproduces `Budget_Line_Unique_Key__c` byte-for-byte); otherwise a
  **progressive structured-field** search runs.
- Business units are matched with **country-suffix tolerance** — a base name like
  `Core Program` matches the org's suffixed `Core Program - KE` (and vice-versa),
  country-scoped so `- KE` never cross-matches `- RW`.
- **One match** → proceed. **Several** → return the *distinguishing* dimensions and ask
  which to use (never merge unrelated Budget Lines). **None** → say so honestly.

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

- **Actions:** `AmaizeAnalyzeHeadroom` (single Budget Line), `AmaizeRankHeadroom` (portfolio).
- **Service/DTOs:** `HeadroomService`, `HeadroomAnalysis`, `BudgetLineDimensions`,
  `AllocationBreakdown`, `HeadroomKeyBuilder`, `HeadroomFormat`, `AmaizeFormat`.
- **Selectors:** `BudgetLineSelector` / `IBudgetLineSelector`,
  `AllocationSelector` / `IAllocationSelector`.
- **Shared calc:** `AmaizeBudgetHeadroom` mirrors the org's Budget Line formulas exactly.

### Agent bundle

- Authoring source: `aiAuthoringBundles/A_maize_ing_Headroom/A_maize_ing_Headroom.agent`
- Compiled/deployed: `genAiPlannerBundles/A_maize_ing_Headroom_v2/` + `bots/A_maize_ing_Headroom/`
- Router sends headroom / funding-gap / room-to-raise / over-allocation /
  secured-/forecast-headroom / funding-availability questions to the Headroom Analysis
  subagent; off-topic and ambiguous requests fall through to their own topics.

### Build, test, deploy

```bash
# Run the headroom Apex tests
sf apex run test --tests HeadroomKeyBuilderTest BudgetLineSelectorTest \
  AllocationSelectorTest HeadroomServiceTest AmaizeAnalyzeHeadroomTest \
  AmaizeRankHeadroomTest --result-format human --target-org <alias>

# Deploy the Apex
sf project deploy start --source-dir force-app/main/default/classes \
  --test-level RunSpecifiedTests --target-org <alias>

# Activate an agent version (creates/switches the live version)
sf agent activate --api-name A_maize_ing_Headroom --version 2 --target-org <alias>
```

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

