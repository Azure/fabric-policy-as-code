# FPAC — Fabric Policy as Code

FPAC is an early-stage PowerShell project for managing Microsoft Fabric policies as code. Its operations export configured policy rules and Policy Sets, build deployment plans, and apply approved plans to Fabric.

Fabric policies and their REST APIs are preview features. Export and deployment only cover workspaces, Policy Sets, and rules visible to the signed-in identity.

For the staged repository setup, live validation plan, module packaging, documentation site, and CI/CD workflows, see the [FPAC implementation and validation roadmap](docs/implementation-and-validation-roadmap.md).

## Why use FPAC

The main benefit of managing Fabric policies as code is controlling, reviewing,
and repeating changes over time, rather than editing live configuration directly.

| In the portal | Managed as code with FPAC |
|---|---|
| An administrator changes live configuration directly. | A proposed change can be reviewed in a pull request before deployment. |
| You inspect the current settings. | Git records changes made through code, including who proposed them and why. |
| Similar policies are configured manually across capacities. | Reusable definitions and parameters produce consistent configurations across environments. |
| Unintended changes must be noticed manually. | Running the plan detects differences between desired state and Fabric. |
| Reversing a change requires reconstructing the previous settings. | A previous Git version can be restored, planned, and redeployed. |
| Governance depends on administrators following a process. | Configured pipelines can enforce tests, approvals, and deployment permissions. |

Portal changes become visible when a plan runs, not immediately. Scheduled drift
detection, approval gates, and automatic reconciliation require pipeline setup.
Restoring an earlier Git version still requires planning and deployment, and
Fabric enforcement changes can take time to propagate.

The portal may be simpler for a single policy set maintained by one administrator.
FPAC becomes more valuable across multiple capacities, contributors, or
environments where consistency, review, and auditability matter.

## Requirements

- PowerShell 7.4 or newer.
- The `Az.Accounts` PowerShell module.
- A Microsoft Entra identity with access to the selected tenant's Fabric workspaces and Policy Sets.
- Fabric delegated API scopes for workspace discovery (`Workspace.Read.All` or `Workspace.ReadWrite.All`) and Policy Set/rule reads (`Item.Read.All` or `Item.ReadWrite.All`).

Install/update Az.Accounts if needed:

```powershell
Install-Module Az.Accounts -Scope CurrentUser
```

## Environments

Define the FPAC environments in [global-settings.jsonc](Definitions/global-settings.jsonc). Every environment belongs to one tenant and is either:

- **Tenant** — requires an explicit Boolean `includeCapacities` on its tenant scope entry. `false` manages only tenant-scoped Policy Sets; `true` manages tenant-scoped and all accessible capacity-scoped Policy Sets in one environment.
- **Capacity** — export only Policy Sets assigned to one of the configured capacity IDs. This allows separate FPAC environments for teams that manage different capacity collections in the same tenant.

The `scope` property is always an array. Its entries must all have the same type; tenant and capacity scopes cannot be mixed in one environment. A tenant environment has exactly one tenant entry, while a capacity environment can have any number of capacity entries.

Example:

```json
{
  "pacOwnerId": "contoso-fpac",
  "desiredStateStrategy": "OwnedOnly",
  "environments": [
    {
      "name": "Tenant",
      "tenantId": "00000000-0000-0000-0000-000000000000",
      "scope": [
        {
          "type": "Tenant",
          "includeCapacities": false
        }
      ]
    },
    {
      "name": "FabricTest",
      "tenantId": "00000000-0000-0000-0000-000000000000",
      "scope": [
        {
          "name": "Development Capacity 1"
        },
        {
          "name": "Development Capacity 2"
        }
      ]
    }
  ]
}
```

The exporter prompts for an environment. For automation, pass its configured name with `-EnvironmentName`. `-GlobalSettingsPath` can select another settings file. Settings are parsed as JSONC, including comments and trailing commas, and the schema is available at [global-settings.schema.json](schemas/global-settings.schema.json).

`includeCapacities` defines the same management boundary for export, planning,
and deployment; it is not an export-only option. It has no default. Missing,
null, or non-Boolean values on a tenant scope cause settings validation to fail
before authentication or deployment. Capacity scope entries must not specify
this property. Existing tenant settings must be updated explicitly, and old
tenant deployment plans must be regenerated.

With `includeCapacities: true`, accessible capacity-scoped resources are inside
the environment's reconciliation boundary. Under `OwnedOnly`, owned resources
omitted from desired state can be deleted; `Full` also permits reconciliation of
unowned resources. Review the entire plan before deploying. Visibility depends
on the caller's Fabric permissions; this setting does not grant tenant-wide
visibility or additional permissions. Avoid declaring the same active scope
under multiple environments; the cross-environment active-scope safeguard still
applies.

Plans and export manifests record `includeCapacities` on their tenant scope.
Deployment refuses a tenant plan whose recorded setting differs from current
configuration. Changing the setting requires building and reviewing a new plan.

## Export

Run from the repository root:

```powershell
.\scripts\operations\Export-PolicyToFPAC.ps1
```

The script uses the current Az.Accounts sign-in context or prompts for Microsoft sign-in if needed. It only issues GET requests to the Fabric APIs. By default, artifacts are written to `Output/<environment>/`. If that environment folder already exists, the exporter asks before deleting and replacing it. `-OutputPath` may be an output root (for example, `.\Output`) or the selected environment folder itself; the script recognizes the latter and will not create a duplicate nested environment folder. To select an environment noninteractively or choose a different output root:

```powershell
.\scripts\operations\Export-PolicyToFPAC.ps1 -EnvironmentName FabricTest `
    -OutputPath .\artifacts
```

Exports contain:

```text
Output/<environment>/
  policyAssignments/    Compact Policy Set deployment declarations
  policyDefinitions/    One FPAC policy file per configured Fabric policy rule
  policySetDefinitions/ Policy Set composition with value-free policy references
  manifest.json         Export summary and failures
```

The canonical JSON Schemas are maintained once under [`schemas/`](schemas/); exports reference those root files instead of copying a schema folder into every environment. Like EPAC artifacts, every policy definition, Policy Set definition, and deployment declaration has `$schema`, an FPAC-friendly `name`, and the natural Fabric content under `properties`. Owned Policy Set definitions also carry FPAC ownership in root `metadata`; individual policy definitions do not carry ownership. Fabric IDs, timestamps, and other incidental service metadata are not exported. Policy definitions and Policy Set definitions are reusable templates, not independent Fabric resources. Files under `policyAssignments/` retain the EPAC-inspired folder name but are FPAC fan-out declarations. Every target pairs the workspace where one concrete Policy Set item lives with the scope where it is active.

Export and desired state use the same three folder names; no folder renaming is
needed when promoting an export. Older exports using `assignments/` and
`policySets/` must be regenerated or explicitly migrated to `policyAssignments/`
and `policySetDefinitions/` before use. Relative `$schema` references may need
adjustment when artifacts are copied to a different directory depth.

Assignment filenames use the Policy Set identifier without an environment
prefix, matching the corresponding Policy Set definition filename. The
assignment's internal `name` and environment-keyed `targets` remain
environment-specific. When promoting a new export over older desired state,
remove superseded environment-prefixed files after backing them up to avoid
duplicate declarations.

The exporter uses the Policy Set-specific APIs (`GET /workspaces/{workspaceId}/policySets/{policySetId}` and `GET /policyRules?beta=true`), rather than the generic item-definition endpoint. Reusable policy definitions declare parameter names, types, and target metadata without values. Policy Set references identify composition and contain empty `parameters` objects. All concrete parameter values are written to the deployment declaration. Values targeting `workspace.id` or `capacity.id` are exported as portable display names when FPAC can resolve them uniquely; planning resolves those names back to live Fabric IDs before deployment. Planning fails when an assignment omits a parameter declared by one of its policies. The exporter writes a manifest when individual workspaces or Policy Sets cannot be read and returns an unsuccessful result for an incomplete export.

## Deployment plans

The capacity-name discovery count excludes Power BI Premium Per User entries
(PP-series SKUs). Those entries remain in the lookup map for reference
resolution; the count does not indicate how many capacities a plan will modify.

The console lists only actual activation changes, or reports
`No activation changes`. Unchanged active Policy Sets remain recorded in the
plan's activation metadata for deployment-time stale-plan validation, but are
not listed as changes in the console.
Activation summaries use concise `Deactivating <workspace>/<policy set> on <scope>`
messages in red and `Activating <workspace>/<policy set> on <scope>` messages in
green. Replacements list both the outgoing and incoming Policy Sets.
Adoption entries include
actual property differences, including status drift, as well as ownership
changes; adoption does not hide changes to existing configuration.
Change-detail headings identify resources as `<workspace>/<policy set>` and
summaries group changes under readable labels such as Ownership, Policies,
Scope, and Status. Detailed ownership changes show the previous and
new owner, using `(unowned)` when no owner exists. Capacity scope values and
activation summaries use resolved capacity names; raw IDs remain in the saved
plan, and unresolved display names are explicitly marked as unavailable.
Deletions show a single red `Delete: <workspace>/<policy set>` summary, even
with `-DetailedOutput`; deleted contents remain in the saved plan, not the console.

FPAC uses the same flat desired-state layout as EPAC:

```text
Definitions/
  policyDefinitions/
  policySetDefinitions/
  policyAssignments/
```

`Output/<environment>/` is a disposable snapshot of live Fabric state. To begin managing exported resources, move the selected policy definitions, Policy Set definitions, and deployment declarations into their corresponding `Definitions/` folders. The files under `Definitions/` then become authoritative.

Deployment declarations select the FPAC environment through each child's environment-keyed `targets`. FPAC follows each selected target to its reusable Policy Set and policy definitions, resolves the assignment's required parameter values, and produces one fully materialized desired Fabric Policy Set per target.

A declaration with one deployment places `displayName`, `status`, `parameters`, and environment-keyed `targets` directly under `properties`; its root `name` is the deployment identity. The `children` array is used only when one file defines multiple deployment variations. Each child has its own identity and shared values, and each target contains `workspace` plus `scope`, so either a direct declaration or child can fan out across multiple workspace and enforcement-scope pairs.

Capacity entries contain only a capacity `name`; omitting `type` identifies them as capacity scopes. During export and planning, FPAC retrieves accessible capacities from Fabric once and resolves names case-insensitively. It fails rather than guessing when a configured name is missing or duplicated. For a capacity environment, every resolved assignment must target one of that environment's resolved capacity IDs.

Planning also resolves every target workspace name against the workspaces returned by Fabric. Workspace matching is case-insensitive. A missing workspace, an inaccessible workspace, a workspace that is not assigned to any Fabric capacity, or duplicate accessible workspace names stop plan generation with an explicit error. The storage workspace's capacity does not need to be the capacity governed by the Policy Set, so one capacity-backed governance workspace can store Policy Sets for several capacities. FPAC removes any existing plan file before discovery so a stale plan cannot remain after validation fails.

Build an EPAC-style deployment plan:

```powershell
.\scripts\Deploy\Build-DeploymentPlans.ps1 -EnvironmentName FabricTestGSlack
```

Add `-DetailedOutput` for Terraform-style field differences. The operation materializes the templates, then classifies each concrete Fabric Policy Set as `new`, `update`, `replace`, `adopt`, `delete`, or unchanged. A storage-workspace or scope-type change requires replacement. Rules, parameters, display names, activation, and capacity-to-capacity reassignment are updates. Stable FPAC ownership IDs allow a display-name change to remain an update. It writes `Output/plans-<environment>/policy-plan.json` only when resource changes exist.

Planning enforces Fabric's activation rules. Any number of inactive Policy Sets may exist, but only one desired Policy Set can be active for a tenant or capacity scope. FPAC checks this both within an environment and across configured environments. Inactive capacity drafts may be unbound; an active capacity Policy Set must identify its governed capacity. The plan records the currently active Policy Set even when the desired activation is already correct, allowing deployment to reject a stale plan if another Policy Set becomes active after planning.

Plan generation is read-only. It does not deploy any changes.

## Ownership and desired-state strategy

FPAC uses `pacOwnerId` from [`global-settings.jsonc`](Definitions/global-settings.jsonc) as its Policy Set ownership boundary. When it writes a Policy Set, it appends a machine-readable marker to the Fabric description:

```text
[[FPAC:v1;owner=contoso-fpac;id=stable-fpac-id]]
```

Human-authored description text remains before the marker and is preserved during export. Root Policy Set `metadata.pacOwnerId` and stable `metadata.fpacId` fields represent the same ownership in desired-state files. Fabric does not expose a general-purpose custom metadata property for these resources, and Fabric tags are tenant-defined IDs that are not returned by ordinary Policy Set item reads, so the description marker is FPAC's authoritative live ownership signal.

All rules inside a managed Policy Set are managed together, not independently
owned. Rule descriptions carry identity-only markers such as
`[[FPAC:v1;id=stable-policy-id]]` to preserve policy names through export and
deployment, including display-name changes. Adoption writes these rule
identities along with set ownership. Legacy rule owner markers remain readable
for identity, and are replaced by identity-only markers when rules are next
written. Legacy policy-definition `metadata.pacOwnerId` is accepted but ignored
and omitted from new exports; it does not create ownership drift.

`desiredStateStrategy` controls cleanup:

- `OwnedOnly` is the safe default. FPAC manages owned Policy Sets and all their rules, preserves unrelated unowned Policy Sets, and requires explicit adoption when an unowned set collides with desired state. Rules absent from desired state are removed from a managed set, regardless of legacy rule ownership markers.
- `Full` treats all visible Policy Sets in the selected management boundary as authoritative. Unowned sets absent from desired state can be deleted, but a matching unowned set still requires explicit adoption.

A Policy Set marked for a different PAC owner must not be silently adopted or modified. Review every `adopt` action and use `-AdoptUnowned` only when FPAC should take ownership of that existing set.

## Deploying a policy plan

Review the generated plan, then preview the deployment without changing Fabric:

```powershell
.\scripts\Deploy\Deploy-Policy.ps1 -EnvironmentName FabricTestGSlack -WhatIf
```

Apply the reviewed plan:

```powershell
.\scripts\Deploy\Deploy-Policy.ps1 -EnvironmentName FabricTestGSlack
```

If the reviewed plan contains adoption actions:

```powershell
.\scripts\Deploy\Deploy-Policy.ps1 -EnvironmentName FabricTestGSlack -AdoptUnowned
```

If activation would replace the Policy Set currently active on a scope, FPAC stops unless the takeover was reviewed and explicitly approved:

```powershell
.\scripts\Deploy\Deploy-Policy.ps1 -EnvironmentName FabricTestGSlack `
    -AllowActivationReplacement
```

The deploy operation validates the plan schema, FPAC owner, desired-state strategy, environment, tenant, and plan-time activation state before applying changes. It resolves workspace and Policy Set IDs from live Fabric state, creates and configures replacement items before activation when Fabric identity constraints permit, synchronizes all rules within managed sets individually through the Policy Rules API, explicitly activates or deactivates items, and handles replacements and deletions. Under `OwnedOnly`, unrelated unowned Policy Sets are preserved, but all rules within a managed set are reconciled. Destructive actions use PowerShell confirmation; pass `-Confirm:$false` only in an approved unattended pipeline.

Deployment output reports completed operations by workspace, Policy Set, and
policy name: creation, rule updates/removals, renames, description changes, and
owner assignment. Activation/deactivation messages identify the tenant or
capacity name and report API acceptance, not immediate enforcement. The final
summary lists only nonzero action counts. Declined actions are marked as
skipped; `-WhatIf` uses "Would" messages and a preview heading that explicitly
states no Fabric changes were applied. Preview and inactive-only deployments
do not claim activation requests were accepted.

New Policy Sets start inactive. Activating a Policy Set while another is active for that scope replaces the active set; the previous item remains in its workspace as an inactive rollback copy unless it is also a planned deletion or replacement. Fabric reports that activation changes can take up to 15 minutes to take effect. A scope administrator is required for activation even when a workspace Contributor can create and configure the item.

Policy parameters are an FPAC authoring feature. During deployment, FPAC resolves parameter references to their effective values and emits the native Fabric `policySet.json` definition. Fabric long-running create and definition-update operations are polled until completion or timeout.

## Tests

```powershell
Invoke-Pester -Script .\tests\*.Tests.ps1
```

See [the Fabric setup and manual policy guide](docs/fabric-setup-and-create-policy.md) for portal prerequisites and policy-rule behavior.

## References

- [Microsoft Fabric policies overview](https://learn.microsoft.com/fabric/governance/fabric-policies-overview)
- [Create and activate a Fabric policy](https://learn.microsoft.com/fabric/governance/fabric-policies-get-started)
- [Manage policies in the OneLake catalog Policies center](https://learn.microsoft.com/fabric/governance/fabric-policies-manage-onelake-catalog)
- [Fabric policies REST APIs](https://learn.microsoft.com/fabric/governance/fabric-policies-rest-api)
- [PolicySet item definition](https://learn.microsoft.com/rest/api/fabric/articles/item-management/definitions/policyset-definition)
- [EPAC operational scripts](https://github.com/Azure/enterprise-azure-policy-as-code/tree/main/Scripts/Operations)
