# FPAC — Fabric Policy as Code

FPAC is an early-stage PowerShell project for managing Microsoft Fabric policies as code. Its operations export configured policy rules and Policy Sets, build deployment plans, and apply approved plans to Fabric.

Fabric policies and their REST APIs are preview features. Export and deployment only cover workspaces, Policy Sets, and rules visible to the signed-in identity.

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

- **Tenant** — enumerate all Policy Sets visible in the tenant, including tenant- and capacity-scoped sets.
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
          "type": "Tenant"
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
  assignments/         Compact Policy Set deployment declarations
  policyDefinitions/   One FPAC policy file per configured Fabric policy rule
  policySets/          Policy Set composition with value-free policy references
  manifest.json        Export summary and failures
```

The canonical JSON Schemas are maintained once under [`schemas/`](schemas/); exports reference those root files instead of copying a schema folder into every environment. Like EPAC artifacts, every policy definition, Policy Set definition, and deployment declaration has `$schema`, an FPAC-friendly `name`, and the natural Fabric content under `properties`. Owned policy and Policy Set definitions also carry FPAC ownership in root `metadata`; Fabric IDs, timestamps, and other incidental service metadata are not exported. Policy definitions and Policy Set definitions are reusable templates, not independent Fabric resources. Files under `assignments/` retain the EPAC-inspired folder name but are FPAC fan-out declarations. Every target pairs the workspace where one concrete Policy Set item lives with the scope where it is active.

The exporter uses the Policy Set-specific APIs (`GET /workspaces/{workspaceId}/policySets/{policySetId}` and `GET /policyRules?beta=true`), rather than the generic item-definition endpoint. Reusable policy definitions declare parameter names, types, and target metadata without values. Policy Set references identify composition and contain empty `parameters` objects. All concrete parameter values are written to the deployment declaration. Values targeting `workspace.id` or `capacity.id` are exported as portable display names when FPAC can resolve them uniquely; planning resolves those names back to live Fabric IDs before deployment. Planning fails when an assignment omits a parameter declared by one of its policies. The exporter writes a manifest when individual workspaces or Policy Sets cannot be read and returns an unsuccessful result for an incomplete export.

## Deployment plans

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

FPAC uses `pacOwnerId` from [`global-settings.jsonc`](Definitions/global-settings.jsonc) as its ownership boundary. When it writes a Policy Set or Policy Rule, it appends a machine-readable marker to the Fabric description:

```text
[[FPAC:v1;owner=contoso-fpac;id=stable-fpac-id]]
```

Human-authored description text remains before the marker and is preserved during export. Root `metadata.pacOwnerId` and stable `metadata.fpacId` fields represent the same ownership in desired-state files. Fabric does not expose a general-purpose custom metadata property for these resources, and Fabric tags are tenant-defined IDs that are not returned by ordinary Policy Set item reads, so the description marker is FPAC's authoritative live ownership signal.

`desiredStateStrategy` controls cleanup:

- `OwnedOnly` is the safe default. FPAC updates and deletes only objects carrying the configured owner marker, preserves unrelated unowned Policy Sets and rules, and requires explicit adoption when an unowned object collides with desired state.
- `Full` treats all visible Policy Sets and rules in the selected management boundary as authoritative. Unowned objects absent from desired state can be deleted, but a matching unowned object still requires explicit adoption.

An object marked for a different PAC owner is never silently adopted or modified. Review every `adopt` action and use `-AdoptUnowned` only when FPAC should take ownership of that existing object.

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

The deploy operation validates the plan schema, FPAC owner, desired-state strategy, environment, tenant, and plan-time activation state before applying changes. It resolves workspace and Policy Set IDs from live Fabric state, creates and configures replacement items before activation when Fabric identity constraints permit, synchronizes owned rules individually through the Policy Rules API, explicitly activates or deactivates items, and handles replacements and deletions. Under `OwnedOnly`, this rule-by-rule reconciliation preserves manually created unowned rules. Destructive actions use PowerShell confirmation; pass `-Confirm:$false` only in an approved unattended pipeline.

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
