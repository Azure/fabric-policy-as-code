# FPAC manual test matrix

This is a test plan, not a record of completed tests. Every case starts as **Not
run**. Use it with the [implementation and validation roadmap](implementation-and-validation-roadmap.md)
and the [configuration and command reference](../README.md).

The first three columns describe the purpose, setup, and execution. The fourth
column defines the pass criteria. IDs are stable so results can be recorded
separately without editing every table.

## Scope and execution order

Test the complete chain:

```text
global-settings.jsonc
  -> policy definitions
  -> Policy Set definitions
  -> assignments / children / targets
  -> materialized plan
  -> reviewed deployment
  -> Fabric read-back
  -> zero-drift plan
  -> enforcement
```

Recommended order:

1. Establish an isolated baseline and run the automated tests.
2. Exercise JSONC, schema, settings, and reference failures without deploying.
3. Create inactive sets; test parameters, reuse, fan-out, and ordinary updates.
4. Test ownership, portal drift, and deletion on disposable resources.
5. Test activation, replacement, stale plans, permissions, and recovery.
6. Test actual enforcement; restore the baseline and record evidence.

This matrix covers representative permutations and high-risk combinations, not
every possible Cartesian product. Repeat the core create/update/zero-drift
cycle with the combinations listed under [combination coverage](#combination-coverage).

### Safety rules

- Use disposable Fabric workspaces and capacities. Back up current desired
  state and record existing active sets before testing.
- Use a unique owner such as `matrix-20261023-01`, not the owner of existing
  managed resources. Names beginning with `FPAC-Matrix-` help identification
  but **do not restrict FPAC discovery, ownership, or deletion**.
- Use `OwnedOnly` and explicit `Inactive` status by default.
- **Do not deploy `Full` against shared capacities or a shared tenant.** It can
  delete any visible in-scope set absent from desired state, not just matrix
  resources. Use a dedicated disposable boundary or a mocked automated test.
- A separate definitions directory is not a Fabric isolation boundary.
  Activation can replace an existing active set even when its owner differs.
- Keep only the selected case's declarations plus any retained resources owned
  by this run inside the selected boundary. Removing an owned assignment is
  potentially a deletion, not just a local test cleanup.
- Never export over authoritative definitions while testing portal drift.
- Stop after any unexpected plan entry or failure. Do not deploy a plan just
  to see whether its unexpected changes are harmless.
- Negative tests must not mutate Fabric. If planning unexpectedly succeeds,
  save the result as a validation gap and stop before deployment.
- Tests marked **Verify** are acceptance probes, not guarantees that the
  current implementation already satisfies them. See
  [implementation-sensitive checks](#implementation-sensitive-checks).
- Tenant activation and enforcement tests require separate administrator
  approval and must run last.
- Mock-only rows are test specifications. Use the matching Pester fixture if
  available; otherwise mark the case **Blocked** until that fixture is added.
  Do not substitute a destructive live experiment for a missing mock.

## Test environment and fixtures

Use PowerShell 7.4+, `Az.Accounts`, and a permitted Fabric identity. Storage
workspaces must be capacity-backed. Use an account with the required delegated
read/write permissions; activation needs the appropriate scope administrator.

The names below match the staged lab layout. Substitute equivalents consistently
if using another lab:

| Alias | Lab resource | Purpose |
|---|---|---|
| Capacity A | `fabrictestgslack` | Primary capacity boundary |
| Capacity B | `fabrictestgslack2` | Secondary capacity/isolation boundary |
| Store A | `FPAC-Governance-A` | Policy Set storage on A |
| Store B | `FPAC-Governance-B` | Policy Set storage on B |
| App A1 / A2 | `FPAC-App-A1` / `FPAC-App-A2` | Rule parameter values and enforcement probes |
| App B1 | `FPAC-App-B1` | Secondary parameter/enforcement probe |
| Unassigned | `FPAC-Negative-Unassigned` | Invalid storage-workspace test |

Create new matrix sets rather than modifying the existing `PolicySet_capacity`,
`PolicySet_1`, or `PolicySet_Tenant`.

### Isolated local working directory

Run from the repository root. These commands create only local test directories:

```powershell
$repo = (Get-Location).Path
$runId = Get-Date -Format 'yyyyMMdd-HHmmss'
$runRoot = Join-Path $repo "Output\manual-tests\$runId"
$defs = Join-Path $runRoot 'Definitions'
$out = Join-Path $runRoot 'Output'
$evidence = Join-Path $runRoot 'evidence'
$settings = Join-Path $defs 'global-settings.jsonc'
$envName = 'Matrix-AB'
$testId = 'L01'

foreach ($path in @(
    $defs, $out, $evidence,
    (Join-Path $defs 'policyDefinitions'),
    (Join-Path $defs 'policySetDefinitions'),
    (Join-Path $defs 'policyAssignments')
)) {
    New-Item -ItemType Directory -Path $path -Force | Out-Null
}
```

The examples below are authoring snippets, not commands to execute against
Fabric. Save them in these new directories. Replace `<TENANT_GUID>` and
`<RUN_ID>` before validation. The relative schema paths assume exactly the
directory layout above.

### Global settings fixture

Save as `Definitions\global-settings.jsonc` inside this run:

```jsonc
{
  "$schema": "../../../../schemas/global-settings.schema.json",
  "pacOwnerId": "matrix-<RUN_ID>",
  "desiredStateStrategy": "OwnedOnly",
  "environments": [
    {
      "name": "Matrix-A",
      "tenantId": "<TENANT_GUID>",
      "scope": [{ "name": "fabrictestgslack" }]
    },
    {
      "name": "Matrix-AB",
      "tenantId": "<TENANT_GUID>",
      "scope": [
        { "name": "fabrictestgslack" },
        { "name": "fabrictestgslack2" }
      ]
    },
    {
      "name": "Matrix-Tenant",
      "tenantId": "<TENANT_GUID>",
      "scope": [{ "type": "Tenant", "includeCapacities": false }]
    }
  ]
}
```

These environments intentionally overlap for boundary tests. Do not declare
the same active scope under more than one environment's targets.

### Reusable policy fixtures

Save as `policyDefinitions\matrix-workspaces.jsonc`:

```jsonc
{
  "$schema": "../../../../../schemas/policy-definition.schema.json",
  "name": "matrix-workspaces",
  "properties": {
    "displayName": "Matrix allowed workspaces",
    "parameters": {
      "allowedWorkspaces": {
        "type": "Array",
        "metadata": { "targetProperty": "workspace.id" }
      }
    },
    "policy": "ItemCreation",
    "conditions": [{
      "type": "Dynamic",
      "targetProperty": "workspace.id",
      "predicate": {
        "operator": "AnyOf",
        "values": ["[parameters('allowedWorkspaces')]"]
      }
    }],
    "effects": [{ "type": "Allow" }]
  }
}
```

For `policyDefinitions\matrix-items.jsonc`, copy that file and change:

- `name` to `matrix-items`.
- `properties.displayName` to `Matrix allowed item types`.
- Parameter name to `allowedItemTypes` and its metadata target to `item.type`.
- The condition target to `item.type`.
- The condition's parameter reference to `[parameters('allowedItemTypes')]`.

Do not put concrete values or `defaultValue` in these reusable definitions.
Use supported item-type values such as `Lakehouse` and `Notebook` for the lab;
confirm the rule shape is accepted by the Fabric preview API before proceeding.

### Reusable Policy Set fixture

Save as `policySetDefinitions\matrix-common.jsonc`:

```jsonc
{
  "$schema": "../../../../../schemas/policy-set.schema.json",
  "name": "matrix-common",
  "properties": {
    "displayName": "Matrix common template",
    "description": "Disposable FPAC matrix policy set.",
    "policies": [
      { "name": "matrix-workspaces", "parameters": {} },
      { "name": "matrix-items", "parameters": {} }
    ]
  }
}
```

For reuse tests, copy it to `matrix-second.jsonc`, change its root `name` to
`matrix-second`, and remove the `matrix-items` reference. Leave per-reference
`parameters` empty. Omitting template ownership metadata lets FPAC use this
run's owner and deployment identities; explicit template IDs are tested
separately.

### Single assignment fixture

Save as `policyAssignments\matrix-a.jsonc`:

```jsonc
{
  "$schema": "../../../../../schemas/assignment.schema.json",
  "name": "matrix-a",
  "properties": {
    "policySetName": "matrix-common",
    "displayName": "FPAC-Matrix-A",
    "status": "Inactive",
    "parameters": {
      "matrix-workspaces": {
        "allowedWorkspaces": { "value": ["FPAC-App-A1"] }
      },
      "matrix-items": {
        "allowedItemTypes": { "value": ["Lakehouse"] }
      }
    },
    "targets": {
      "Matrix-AB": [{
        "workspace": "FPAC-Governance-A",
        "scope": { "name": "fabrictestgslack" }
      }]
    }
  }
}
```

The assignment determines the concrete set's display name, status, storage
workspace, scope, and parameter values. Template display names are not a
substitute for assignment deployment names.

### One assignment, different parameters at different scopes

For this variation, move `matrix-a.jsonc` outside the active definition
directory first so the same target is not declared twice. Save
`policyAssignments\matrix-variations.jsonc`:

```jsonc
{
  "$schema": "../../../../../schemas/assignment.schema.json",
  "name": "matrix-variations",
  "properties": {
    "policySetName": "matrix-common",
    "children": [
      {
        "name": "matrix-variation-a",
        "displayName": "FPAC-Matrix-Variation-A",
        "status": "Inactive",
        "parameters": {
          "matrix-workspaces": {
            "allowedWorkspaces": { "value": ["FPAC-App-A1"] }
          },
          "matrix-items": {
            "allowedItemTypes": { "value": ["Lakehouse"] }
          }
        },
        "targets": {
          "Matrix-AB": [{
            "workspace": "FPAC-Governance-A",
            "scope": { "name": "fabrictestgslack" }
          }]
        }
      },
      {
        "name": "matrix-variation-b",
        "displayName": "FPAC-Matrix-Variation-B",
        "status": "Inactive",
        "parameters": {
          "matrix-workspaces": {
            "allowedWorkspaces": { "value": ["FPAC-App-B1"] }
          },
          "matrix-items": {
            "allowedItemTypes": { "value": ["Notebook"] }
          }
        },
        "targets": {
          "Matrix-AB": [{
            "workspace": "FPAC-Governance-B",
            "scope": { "name": "fabrictestgslack2" }
          }]
        }
      }
    ]
  }
}
```

**Parameter boundary:** one child fans out its own values to all its targets.
Different values require different children or separate assignments. Targets
do not support their own `parameters`. Children do not inherit a root parameter
map; supply each child's complete required values. Specify every child status
explicitly instead of depending on defaults/inheritance.

## Command recipes used in the matrix

Set `$testId` for the row and `$envName` for the intended environment before each
case. Stop after any command failure. Never use an earlier reviewed plan after
changing definitions, settings, or the relevant live state.

### S - parse and schema-check authoring files, without Fabric calls

The schema/editor checks and runtime checks are distinct: planning reads JSONC
but does not automatically enforce every authoring schema constraint.

```powershell
# Dot-sourcing loads helpers but does not execute the planning operation.
. (Join-Path $repo 'scripts\Deploy\Build-DeploymentPlans.ps1')

Get-FpacGlobalSettings -Path $settings | Out-Null
$schemaByFolder = @{
    policyDefinitions = 'policy-definition.schema.json'
    policySetDefinitions = 'policy-set.schema.json'
    policyAssignments = 'assignment.schema.json'
}
foreach ($folder in $schemaByFolder.Keys) {
    $artifacts = Get-FpacArtifactCollection -Path (Join-Path $defs $folder)
    foreach ($artifact in $artifacts.Values) {
        $valid = Test-Json -Json ($artifact | ConvertTo-Json -Depth 100) `
            -SchemaFile (Join-Path $repo "schemas\$($schemaByFolder[$folder])")
        if (-not $valid) { throw "Schema validation failed: $folder/$($artifact.name)" }
    }
}
```

For settings constraints beyond runtime parsing, use the editor's
`global-settings.schema.json` diagnostics as well. Do not run S before a negative
test when the purpose is specifically to determine what planning itself rejects;
record S and P results separately.

### P - build a fresh plan

```powershell
& (Join-Path $repo 'scripts\Deploy\Build-DeploymentPlans.ps1') `
    -DefinitionsPath $defs -GlobalSettingsPath $settings `
    -OutputPath $out -EnvironmentName $envName -DetailedOutput
```

### R - review and preserve the exact actionable plan

Inspect every action bucket, both `desired` and `deployed` for changed resources,
and `activationChanges`. Confirm the entire plan is safe, not just the test row.
Only after successful P and review:

```powershell
$planFile = Join-Path $out "plans-$envName\policy-plan.json"
$plan = Get-Content -LiteralPath $planFile -Raw | ConvertFrom-Json -Depth 100
$plan.policySets | ConvertTo-Json -Depth 100
$plan.activationChanges | ConvertTo-Json -Depth 100
$reviewedPlan = Join-Path $evidence "$testId-$(Get-Date -Format 'HHmmssfff')-reviewed-plan.json"
Copy-Item -LiteralPath $planFile -Destination $reviewedPlan
```

R is not applicable after a zero-change P because no actionable plan should
exist at `$planFile`. Preserved evidence copies are not automatically deleted.

### V - preview that reviewed plan

```powershell
& (Join-Path $repo 'scripts\Deploy\Deploy-Policy.ps1') `
    -PlanFile $reviewedPlan -GlobalSettingsPath $settings `
    -EnvironmentName $envName -WhatIf
```

### D - apply that reviewed plan

```powershell
& (Join-Path $repo 'scripts\Deploy\Deploy-Policy.ps1') `
    -PlanFile $reviewedPlan -GlobalSettingsPath $settings `
    -EnvironmentName $envName
```

Use `-AdoptUnowned` on V and D when the reviewed plan adopts unowned sets. Use
`-AllowActivationReplacement` only when the reviewed plan intentionally replaces
the active set for a scope. Both gates currently apply to previews too. Keep
normal confirmation prompts except in the dedicated unattended-deployment test.

### E - export live state for read-back

```powershell
& (Join-Path $repo 'scripts\operations\Export-PolicyToFPAC.ps1') `
    -GlobalSettingsPath $settings -EnvironmentName $envName `
    -OutputPath (Join-Path $runRoot "exports\$testId-$(Get-Date -Format 'HHmmssfff')")
```

Inspect the manifest and the actual rules, status, storage workspace, and scope.
Use the portal or a read-only API read to record item/rule IDs when identity
preservation matters; exported authoring files intentionally omit service IDs.
Do not copy E back over `$defs` during reconciliation tests.

### Z - prove convergence

After successful D and live read-back, repeat P twice without changing anything.
Both runs must show zero resource changes and no activation changes. The working
plan file under `$out\plans-<environment>` must not exist. If Fabric is still
propagating, wait and re-read; do not waive persistent drift or repeatedly deploy
without diagnosing it.

**Cycle** below means **S -> P -> R -> V -> D -> E -> Z**. For negative cases,
stop at the expected failure. Apply all safety rules even when a row says Cycle.

## 1. Global settings, discovery, and boundaries

| Test / what it accomplishes | Setup instructions | Run instructions | Expected result |
|---|---|---|---|
| G01 - Capacity environment baseline | Use the fixture settings and single inactive assignment. | S; P with `Matrix-AB`; inspect A scope. | Capacity names resolve; only the declared instance is created/updated. |
| G02 - Single-capacity restriction | Select `Matrix-A`; give its target an A scope, then separately a B scope. | P for each variant; do not deploy the B variant. | A is accepted; B is rejected as outside the environment. |
| G03 - Tenant-only boundary | Use `Matrix-Tenant` with `includeCapacities: false`; test a tenant assignment, then a capacity assignment. | S; P for each; E for tenant discovery. | Tenant assignment is allowed; capacity assignment rejected; export excludes capacity sets. |
| G04 - Inclusive tenant boundary | Set `includeCapacities: true`; target one tenant set and inactive sets on A/B. | P and E only initially; D only in an approved disposable tenant. | All accessible in-boundary scope types are included with original scopes. |
| G05 - Explicit tenant option | Separately remove `includeCapacities`, set `null`, `"false"`, and `1`. | P for each variant, even while selecting another valid environment. | Settings fail before discovery/mutation; there is no tenant default. |
| G06 - Invalid scope combinations | Separately mix tenant/capacity entries, add two tenant entries, add `includeCapacities` to a capacity entry, and use explicit global `type: "Capacity"`. | S and P separately. | Each invalid configuration is rejected; global capacity entries use `name` without `type`. |
| G07 - Environment identity validation | Separately use a missing name, duplicate names differing only in case, invalid tenant GUID, empty environment list, or empty scope list. | P for each variant. | Explicit settings errors; no plan available for deployment. |
| G08 - Selection and casing | Use a nonexistent selected environment; then vary the case of valid environment, capacity, and workspace names. | P for each; compare the valid materialized identities. | Unknown environment fails; case variants resolve consistently without duplicate resources. |
| G09 - Capacity discovery failures | Use nonexistent and duplicate configured capacity names. For duplicate live names, use mocked discovery if unavailable in the lab. | P; use automated/mocked checks for fabricated responses. | No guessing; explicit missing/ambiguous/duplicate-name error. |
| G10 - Defaults and unsupported settings values | In a read-only settings copy, omit strategy/owner, then separately use an invalid strategy or owner containing spaces. | Parse settings/S; P only after reviewing effective owner. | Defaults are `OwnedOnly` and `fpac`; invalid values fail. Never deploy an accidental owner change. |
| G11 - Cross-environment activation conflicts | Declare two active deployments on A under `Matrix-A` and `Matrix-AB`; repeat with tenant scope; repeat with one name and one ID for the same capacity. | P only. | Same-scope activation must be rejected. Name/ID equivalence is a Verify case; record any detection gap. |
| G12 - Scope versus storage independence | Store an inactive B-scoped set in Store A; use `Matrix-AB`, then `Matrix-A`. | P and E; Cycle only for the valid B-scoped declaration. | Storage capacity does not change administrative scope; the primary-only environment must not manage B. |
| G13 - Workspace eligibility | Separately target a nonexistent workspace, an inaccessible workspace, and the unassigned workspace. | P only for each. | Clear inaccessible/missing/capacity-backed-storage error before writes. |
| G14 - PPU discovery count | With PPU visible, leave normal A/B scopes unchanged. | P; inspect the capacity discovery count and saved normal scopes. | PPU is excluded from the reported assignable-capacity count, without losing lookup entries or altering A/B targeting. |

## 2. JSONC, schemas, and authoring identity

| Test / what it accomplishes | Setup instructions | Run instructions | Expected result |
|---|---|---|---|
| F01 - JSONC support everywhere | Add line comments, block comments, and trailing commas to settings and one file in each of the three definition folders. Include a description containing `https://example.test//text`. | S; P; compare with the comment-free baseline. | Same semantic plan; comment-like text inside strings is preserved. |
| F02 - Legacy JSON compatibility | Rename one definition to `.json`, leaving other definitions `.jsonc`. | S; P. | Mixed extensions remain readable with unchanged references. |
| F03 - Duplicate artifact detection | Keep `.json` and `.jsonc` copies with the same root `name`; repeat for each folder. | S and P separately. | Duplicate identity error, not silent preference for one extension. |
| F04 - Filename independence | Rename each file without changing its root `name` or references. | S; P from zero drift. | No deployment differences caused solely by filenames. |
| F05 - Invalid documents | Separately break JSONC syntax and remove `name` or `properties`. | S and P separately. | Source file is identified in an explicit parse/structure error. |
| F06 - Schema-only violations | Add an unknown property; put `defaultValue` in a policy parameter; put `parameters` on a target; use invalid status. | S first. In a separate safe experiment run P without S. | S rejects each schema violation. Record any runtime acceptance as a validation gap; never deploy invalid input. |
| F07 - Container/reference shapes | Replace expected arrays/maps with scalars; test empty children/targets and a malformed `{ "value": ... }` wrapper. | S; optionally P to assess diagnostics. | Invalid schemas fail; runtime failures remain explicit rather than producing a plausible deployment. |
| F08 - Description fidelity and limits | Use descriptions containing quotes, backslashes, newlines, and Unicode escapes. Separately exceed the set description's 256-character schema limit. | S; Cycle for valid text; S only for excessive length. | Valid human text survives read-back/export alongside FPAC markers; overlong set description fails schema validation. |

## 3. Policy definitions and parameter materialization

| Test / what it accomplishes | Setup instructions | Run instructions | Expected result |
|---|---|---|---|
| P01 - Required parameter values | Remove `allowedWorkspaces` from the assignment's `matrix-workspaces` entry. Repeat for a child. | P only. | Missing required parameter is identified; no implicit default. |
| P02 - Unknown policy/parameter override | Separately add an override for `missing-policy` and for `missingParameter` on a real policy. | P only. | Explicit reference/parameter error. |
| P03 - Name and ID resolution | Use workspace names, then their accessible IDs, in `allowedWorkspaces`; repeat for a valid `capacity.id` parameter fixture. | P and compare saved resolved values; Cycle for equivalent variants if needed. | Equivalent names/IDs converge; payloads use IDs; console uses names where resolvable. |
| P04 - Unresolvable reference value | Use a nonexistent workspace/capacity name and an inaccessible/unknown GUID in a targeted parameter. | P only. | Error identifies the inaccessible name/ID rather than passing it through as a valid reference. |
| P05 - Array cardinality | Try one value, multiple values, and an empty array for each array parameter; separately try a scalar for an array parameter. | S; P; deploy only values valid for the Fabric rule contract. | Arrays retain their shape; no truncation. Record deliberate scalar normalization versus schema/API restrictions. |
| P06 - Parameter change locality | Add App A2 to only assignment A's `allowedWorkspaces`, while assignment B consumes the same policy. | Cycle; inspect all affected sets and B's live rule. | Only A's rule values change; B remains byte/semantically unchanged in read-back. |
| P07 - Rule display-name change | Change `matrix-workspaces.properties.displayName`, keeping its root `name`. | Record rule IDs; Cycle. | Consumer rules are renamed through stable identity; no accidental extra rules; IDs preserved where API update is supported. |
| P08 - Rule description change | Change only the reusable policy's human description. | Cycle; E; inspect live description/identity marker. | Human text changes and survives export; stable rule identity remains intact. |
| P09 - Conditions and multiple parameters | Add a second valid dynamic condition with a second declared parameter and provide both assignment values. Change only one value afterward. | Cycle twice; inspect both concrete predicates. | Every reference resolves; unchanged condition values remain unchanged. |
| P10 - Missing expression parameter | Use `[parameters('undeclared')]` in a predicate without declaring/supplying it. | S; P; do not D if P accepts it. | Must fail before a write; if detected only while building a deployment payload, record a preflight gap. |
| P11 - Policy type change | Change a rule to another valid policy type with a valid complete definition. | Record old rule ID; Cycle in a disposable inactive set. | Rule is deleted/recreated as required, unrelated rules retained, final type correct, zero drift. |
| P12 - Effect-only change (Verify) | Change only `effects` to another supported effect/configuration. Use a mocked contract test if the API offers no safe live alternative. | P; inspect request construction before any D; then controlled Cycle if supported. | Desired effect must actually reach Fabric and converge. Current ordinary PATCH omits `effects`; do not count plan output alone as success. |
| P13 - Non-reference values stay literal | Use an `item.type` or other non-reference parameter containing strings resembling resource names/IDs. | P; inspect payload and display copies. | Only metadata-tagged resource references are resolved; unrelated values are unchanged. |
| P14 - Null, unsupported values, and declared types (Verify) | Separately supply null, a number/object instead of a rule's expected value, an unknown item type, and an unsupported declared parameter type. | S and P separately; inspect a mocked API payload; no live D with invalid rule values. | Record which layer rejects each value. Runtime parameter type checking is not exhaustive; API rejection must remain explicit, never reported as convergence. |

## 4. Policy Set composition and shared policies

| Test / what it accomplishes | Setup instructions | Run instructions | Expected result |
|---|---|---|---|
| S01 - Missing referenced policy | Change a set reference to `missing-policy`; separately remove the referenced policy file. | P only. | Missing definition error, not a partial rule collection. |
| S02 - Values belong in assignments | Put a concrete value in `matrix-common.properties.policies[].parameters`. | S and P separately. | Rejected with guidance to move values to the assignment. |
| S03 - Duplicate rule identity/name | Reference one policy twice; separately reference two different policies with the same display name, including case-only variants. | P only. | Ambiguous overrides or duplicate concrete rule names are rejected. |
| S04 - One policy, two set templates | Deploy `matrix-common` and `matrix-second` through distinct inactive assignments. Change the shared policy's condition or description. | Cycle; inspect both sets and their independent rule IDs/values. | Both consumers receive the shared definition change; per-assignment parameter values remain separate. |
| S05 - Add/remove a policy reference | Add `matrix-items` to the second set and its assignment values; later remove that reference and its override. | Cycle after each edit. | Only the intended set gains/loses the rule; the shared policy file and other consumers survive. |
| S06 - Empty composition | Use `policies: []` with assignment `parameters: {}` on a new inactive set. | S; Cycle if accepted by Fabric. | Empty set round-trips without fabricated rules or repeated drift; an API restriction is recorded explicitly. |
| S07 - Unused templates | Add an unreferenced policy and set template; then edit/delete only those unused templates. | S; P from zero drift. | No concrete resource changes caused by unused templates; all authoring files must still parse. |
| S08 - Template versus deployment name | Change only the set template's `properties.displayName`, keeping assignment display names fixed. Then separately change template description. | P for name-only edit; Cycle for description edit. | Assignment remains naming authority; template description updates all concrete consumers. |
| S09 - Template identity rename | Rename a template's root `name` and update all assignment `policySetName` references, keeping deployment identities unchanged. | P; review before Cycle. | Composition resolves without unintended creates/deletes; investigate any identity drift rather than accepting a replacement by default. |

## 5. Assignments, children, fan-out, and reuse

| Test / what it accomplishes | Setup instructions | Run instructions | Expected result |
|---|---|---|---|
| A01 - Missing set template | Change `policySetName` to `missing-set`. | P only. | Clear missing-set error. |
| A02 - One set, two assignments | Copy `matrix-a.jsonc`; change root name to `matrix-b`, display name to `FPAC-Matrix-B`, store/scope to B, and values to App B1/Notebook. Keep `policySetName: matrix-common`. | Cycle; inspect both concrete items and every parameter. | Two independent sets use one template; no parameter or identity leakage. |
| A03 - Same template across workspaces | Target the same template/display name in Store A and another capacity-backed workspace. Keep both inactive. | Cycle; inspect each workspace and saved identity. | Distinct workspace/set pairs are materialized; no accidental coalescing. |
| A04 - Same child, many targets | Add Store B/B to one child's targets array without changing its parameters. | P; Cycle with valid shared values. | One instance per target; all receive the same child values, not target-specific guesses. |
| A05 - Different values per scope | Use the complete two-child `matrix-variations` example above. | Cycle; read both rules in A and B. | A receives App A1/Lakehouse; B receives App B1/Notebook. |
| A06 - Child-local update | After A05, change only variation B's `allowedItemTypes` to a different valid list. | P must contain only B's intended update; Cycle. | A's status, IDs, rules, and values remain unchanged. |
| A07 - Fan-out of several children | Give each of two children two distinct storage targets; keep distinct child display names and all instances inactive. | Cycle; enumerate the four workspace/name pairs. | Exactly four concrete sets, correct parameter group per child, no cross-child sharing of mutable values. |
| A08 - No root-parameter inheritance | Put required values only at the root while children omit their own maps. | S and P separately. | Child values are not inherited; missing-parameter failure. Repair by supplying complete child maps. |
| A09 - No target-parameter override | Put different `parameters` inside each target rather than using children. | S only; do not deploy schema-invalid targets. | Schema rejects this shape; use A05 instead. |
| A10 - Duplicate concrete destination | Make two assignments/children resolve to the same workspace and set display name; repeat case variants and duplicate targets. | P only. | Explicit duplicate materialized destination/instance error. |
| A11 - Target selection | Give a file only `Matrix-AB` targets; plan `Matrix-A`. Then test a misspelled target environment key. | P only and inspect deletions carefully. | Nonselected keys produce no instances. A typo can make owned resources absent and deletable; unknown-key validation is not assumed. |
| A12 - Add/remove one fan-out target | Add a B target to an existing A-only declaration; then remove only B, retaining A. | P/R before each D; E and Z after each. | Only intended new/delete actions occur. Adding/removing a target must not silently re-identify surviving instances; record any churn as a Verify failure. |
| A13 - Shared-template rename after fan-out (Verify) | After A02/A04, rename only one concrete set through its assignment. Repeat after deliberately sharing an explicit template `metadata.fpacId`. | P; inspect ownership alignment before any D; then controlled Cycle. | Only selected instance is renamed. Shared template IDs must not select/rename an arbitrary sibling or produce unexplained ambiguity. |
| A14 - Environment-isolated parameter variations | Supply separate children targeting different environments with distinct values and nonconflicting active scopes. | P for each environment; apply one environment at a time; E/Z. | Only selected environment instances and their values change. |
| A15 - Assignment scope encodings (Verify) | Replace a target's capacity name with its valid ID; then test a known name paired with the wrong ID, unsupported scope type, and unknown capacity GUID under an inclusive tenant environment. | S/P for each; no D for invalid variants. | Valid name/ID forms resolve equivalently; known mismatches/types fail. Unknown-ID accessibility validation is an acceptance probe, not a guaranteed guard today. |
| A16 - Child status defaults (Verify) | With root `status: "Inactive"`, omit child status; separately omit all statuses. Keep a competing active declaration to expose inconsistent defaults. | S and P separately; do not D; compare expansion versus cross-environment conflict diagnostics. | Default/inheritance behavior must be consistent. Current expansion and cross-environment validation can infer different statuses; use explicit child statuses until resolved. |
| A17 - Legacy expanded assignments | In a copy of the direct assignment, replace `targets` with legacy `environment: "Matrix-AB"`, `workspace`, and `scope` properties, retaining the other deployment fields. | S/P; compare with equivalent direct-form materialization; controlled Cycle if compatibility is required. | Supported legacy form produces the same concrete set and parameter values; not a separate duplicate deployment. |

## 6. Baseline lifecycle and zero drift

| Test / what it accomplishes | Setup instructions | Run instructions | Expected result |
|---|---|---|---|
| L01 - Create entirely from code | Use new `FPAC-Matrix-A`, inactive, absent in Fabric. | Cycle. | One new set with the two correct rules; no adoption; zero drift. |
| L02 - Repeatable zero drift | Leave a successfully deployed definition unchanged. | Z; repeat after a new PowerShell session/sign-in. | No changes/activation actions; working plan file is absent, not stale. |
| L03 - Portal parameter drift correction | After L02, add App A2 to the live workspace rule in the portal, without changing code. | P/R/V/D/E/Z; never promote E into definitions. | Plan removes only unintended values; deployment restores code values. |
| L04 - Code parameter update | Add App A2 to the assignment instead of the portal. | Cycle. | New allowed value reaches Fabric, then no repeated change. |
| L05 - Portal-added rule removal | Add a harmless extra rule manually inside the owned matrix set. | Cycle. | Extra rule is identified and removed; set ownership covers all contained rules. |
| L06 - Portal-deleted rule recreation | Delete one rule manually while leaving the owned set. | Cycle. | Missing rule is recreated with stable FPAC identity; other rule retained. |
| L07 - Live set manually removed | Delete only the disposable matrix set manually, leaving definitions unchanged. | Cycle. | Recreate action, not update of a nonexistent item; final contents match. |
| L08 - Set rename | Change the assignment's display name, preserving assignment/root ownership identity. | Record item ID; Cycle. | Update/rename, not unwanted recreation; item ID preserved when identity resolves. |
| L09 - Storage replacement | Change only storage workspace from Store A to Store B, keeping administrative scope A. | P must report replacement; R/V/D/E/Z. | New storage item is correct, old item removed, scope/parameters preserved. |
| L10 - Failure after partial progress | Use mocked API failure on a later write; live version only with an approved disposable fixture. | Run deployment fault test; inspect live state; rebuild P before recovery. | Earlier accepted writes remain visible; no false overall success/rollback claim; fresh plan enables recovery. |

## 7. Ownership, strategy, adoption, and deletion

| Test / what it accomplishes | Setup instructions | Run instructions | Expected result |
|---|---|---|---|
| O01 - OwnedOnly ignores unrelated sets | Manually create inactive `FPAC-Matrix-Unmanaged`, with no definition and no FPAC marker. Keep `OwnedOnly`. | P/E; do not add it to definitions. | No delete/adopt action for this unrelated set. |
| O02 - Matching unowned adoption | Manually create inactive `FPAC-Matrix-Adopt`; create a matching assignment with code-controlled rule values. | P/R; V and D without the switch must fail; repeat with `-AdoptUnowned`; E/Z. | Ownership is assigned once, intended configuration reconciled, rule identities recorded; no repeated adoption. |
| O03 - Adoption plus property drift | Before O02 deployment, make live status/rules differ from desired state. | P/R/V/D with adoption approval, E/Z. | Plan exposes ownership plus real changes; deployment applies both, not ownership alone. |
| O04 - Owned set omitted | Deploy disposable `FPAC-Matrix-Delete`, then move only its assignment outside the active definitions tree. | P/R/V/D/E/Z. | Owned omitted item is deleted under `OwnedOnly`; unrelated unowned set survives. |
| O05 - Full deletes omitted unowned sets | In a dedicated disposable boundary, create `FPAC-Matrix-Unmanaged`; select `Full` and leave it undeclared. | P/R/V; D only after reviewing every deletion; E/Z. | Omitted unowned set is deleted. `Full` is not an automatic import/adoption of everything. |
| O06 - Declared sets under both strategies | Repeat matching-unowned adoption under `OwnedOnly` and `Full`, with no unrelated resources at risk. | P/V/D with current adoption gate; E/Z each time. | Declared unowned matches are adopted in either strategy; strategy changes do not bypass approval. |
| O07 - Foreign owner collision | Use a disposable set carrying a different owner's real marker and a matching desired destination. Separately set a template's root owner to another owner. | P only; mocked deployment preflight for ownership changed after planning. | Explicit refusal; `-AdoptUnowned` is not authorization to take another owner. |
| O08 - Foreign omitted set under Full (Verify) | Construct an omitted foreign-owned set in mocked inventory; do not use a shared live environment. | Automated/mocked plan/deploy inspection only. | Record policy decision and safety gap: current `Full` deletion classification does not exempt foreign owners merely because they are foreign. |
| O09 - Legacy rule markers | In a disposable owned set, use legacy per-rule owner markers, including a different legacy rule owner. Keep valid stable rule IDs. | P; change one rule; D/E/Z. | No independent rule-ownership drift; rewritten rule markers are identity-only; set ownership controls reconciliation. |
| O10 - Owner changes and stale ownership | After R, change configured owner; separately change the live target's owner or remove its ownership marker. | V/D must stop where supported; inspect before any real write. | Settings-owner mismatch fails; update/adoption refuses changed foreign ownership. Owner loss requires a new adoption plan. |

## 8. Status, scope, activation, and tenant behavior

| Test / what it accomplishes | Setup instructions | Run instructions | Expected result |
|---|---|---|---|
| T01 - Inactive to active | Use a narrow matrix set on a disposable capacity with no competing active set. Set assignment `Active`. | Cycle with scope-admin approval; verify effective active item. | Activation accepted, correct scope enforced, no repeated activation changes. |
| T02 - Active to inactive | Change the active set's assignment to `Inactive`. | Cycle. | Explicit deactivation in plan and accepted-result output; final inactive state. |
| T03 - Status drift both directions | Separately activate desired-inactive and deactivate desired-active sets manually. | Cycle after each portal change. | Plan detects each mismatch and restores declared status. |
| T04 - Unbound inactive draft (Verify) | Use `scope: { "type": "Capacity" }`, `Inactive`; then separately set `Active` while still unbound. | P; Cycle only for valid inactive draft. | Inactive unbound draft supported; active unbound rejected. Record whether Fabric drops inactive binding and causes persistent scope drift. |
| T05 - Capacity reassignment | Move an active A-scoped set to B, then test an inactive A-to-B reassignment separately. | P/R/V/D/E/Z with approved replacement flag if B is occupied. | Active move deactivates old scope and activates B without storage replacement. Inactive binding persistence is a Verify case, not assumed. |
| T06 - Competing active set | Manually activate disposable `FPAC-Matrix-Current` on the scope desired by another matrix set. Retain its definition if it is owned and should survive. | P/R; V/D without replacement switch fail; repeat with `-AllowActivationReplacement`; E/Z. | Outgoing/incoming identities are clear; desired set active; outgoing set inactive unless separately deleted. |
| T07 - Multiple active declarations | Set two distinct desired sets on the same capacity/tenant scope to Active; then repeat with distinct A/B scopes. | P only for conflict; Cycle for valid distinct scopes. | Same-scope conflict rejected; distinct scopes independent; multiple inactive drafts allowed. |
| T08 - Scope-type replacement | Change a disposable capacity deployment to tenant scope or vice versa in an explicitly inclusive environment. | P/R; tenant-admin-approved V/D/E/Z only. | Replacement classification; no duplicate active scope; old item removed safely. |
| T09 - Inactive draft cannot deactivate another set | Leave a different approved set active; declare an unrelated matrix draft inactive at that scope. | P/R/V only initially; controlled D if safe. | No deactivation of the other active set solely because this draft is inactive. |
| T10 - Tenant permission and reach | Use a narrow harmless tenant rule; first use an identity lacking tenant activation rights, then an approved tenant admin. | Review P; approved D failure/success tests; read back and promptly deactivate. | Permission failures explicit, no success claim; successful tenant change has the intended administrative reach only. |

## 9. Deployment validation, stale plans, and isolation

| Test / what it accomplishes | Setup instructions | Run instructions | Expected result |
|---|---|---|---|
| D01 - WhatIf never writes | Prepare an actionable reviewed plan containing safe representative action types. Record live IDs/configuration first. | V with only necessary approval switches; read back; compare baseline. | No writes, identical state; "Would" messages and preview heading; zero completed-action counts. |
| D02 - Interactive confirmation | Prepare one disposable update and decline its confirmation. Repeat with approval. | D without `-Confirm:$false`; then fresh P/R/D. | Declined action skipped and unchanged; approved action applied. |
| D03 - Unattended deployment | Use the same reviewed harmless update after testing prompts. | D with `-Confirm:$false`; E/Z. | Prompts suppressed, but validation and adoption/activation gates still enforced. |
| D04 - Wrong settings or plan environment | After R, separately change environment selection, tenant GUID, owner, and strategy in test settings. | V only for each mismatch. | Deployment rejects incompatible plan/settings before mutation. |
| D05 - Tenant plan compatibility | After a tenant R, toggle `includeCapacities`; separately remove it from the saved test plan's tenant scope. | V only. | Mismatched setting or legacy plan rejected. |
| D06 - Out-of-bound plan entries | Tamper only a copy of a test plan: put B or tenant resources into a primary-only environment. Repeat in every action bucket and both desired/deployed sides. | V only; preferably use existing mocked boundary tests. | All invalid sides/buckets rejected before mutation. |
| D07 - Stale activation state | After R, switch the live active set to a different disposable set, or activate one where none was expected. | V only initially. | Explicit expected-versus-current activation error; fresh P required. |
| D08 - Stale ordinary rule change (Verify) | After R, change a live rule without changing active-set identity. | V and inspect; controlled D only if overwrite is intended. | Record current limit: deployment does not perform a full rule-drift fingerprint check. Do not claim all stale plans are rejected. |
| D09 - New-item collision or missing target | After R for a create, manually create its destination; separately delete/rename a planned update/delete target. | V only. | Resource-existence validation stops the affected action; no mistaken target selected. |
| D10 - Invalid/missing/empty plan | Use missing file, malformed JSON, schema-invalid plan, and a schema-valid zero-change plan separately. | V only. | Explicit failure, not a success-shaped no-op. A normal zero-drift P leaves no working plan. |
| D11 - Primary isolation with B sentinel | Deploy an inactive B sentinel under `Matrix-AB`. Declare retained A resources under `Matrix-A` and avoid overlapping active scopes. Record B ID/status/scope/rules. | P/R/V/D for `Matrix-A`; read B again; Z on A. | No B action in any bucket; every recorded B property remains unchanged. |
| D12 - Reviewed artifact versus edited files | R a harmless change, then edit desired files without replacing the preserved plan. Do not accidentally approve its stale application. | V against the preserved plan; compare to a fresh P. | Preview uses the saved plan, not new definitions; operational process requires a newly reviewed plan after edits. |
| D13 - Multiple instances and stable IDs (Verify) | With shared-template fan-out deployed, rename one instance or move its workspace. Include the explicit-ID variation from A13. | P/R; inspect alignment; controlled Cycle. | No sibling hijacking, duplicate owner/ID match, or unintended deletion/recreation. Capture a defect if alignment is ambiguous. |
| D14 - Read permission is not write permission | R a harmless update; use an identity that can read the target but cannot update it. Use mocks if a suitable lab identity is unavailable. | V, then approved D; inspect live state and failure output. | Preview may pass because it does not execute write helpers; D must report the authorization failure, with no false success or unexpected writes. |
| D15 - Retries, expired authentication, and timeouts | In mocked API fixtures, separately return 429/transient failures, 401/403, and a long-running operation that never completes. Include success after a retry. | Run the relevant Pester API/deploy fixture with bounded retry/timeout settings; record attempts and outcomes. | Retryable failures are bounded; permanent failures/timeouts explicit; eventual success reported only after API acceptance/completion as appropriate. Missing fixtures are Blocked, not passed. |

## 10. Export and promotion

| Test / what it accomplishes | Setup instructions | Run instructions | Expected result |
|---|---|---|---|
| E01 - Canonical JSONC export | Deploy one safe matrix set, then export to a fresh snapshot root. | E; inspect manifest, files, and schema references. | Three canonical authoring folders; `.jsonc` definitions; `.json` manifest; every referenced path exists. |
| E02 - Portable names and round trip | Use workspace/capacity references and human descriptions; include new identity-only and legacy rule markers in separate fixtures. | E; copy only selected artifacts into a fresh separate test definitions root, adapt environment keys/schema depth, S/P. | Names/IDs resolve equivalently; human text preserved; no ownership noise or rule-value drift. Never replace the original desired state to hide drift. |
| E03 - Shared-policy export (Verify) | Deploy A02/S04 so multiple sets contain the same stable policy ID. | E into a fresh destination; inspect completeness and duplicate-file handling. | A complete reusable export should preserve shared references without overwriting definitions. Current duplicate filename detection may fail; record the limitation. |
| E04 - Scope filtering independent of storage | Place A/B/tenant sets in a central capacity-backed workspace. | E for primary-only, AB, tenant-only, inclusive tenant variants. | Inclusion follows administrative scope, not storage capacity; manifest counts/exclusions agree. |
| E05 - Partial discovery failure | Use an identity denied access to a selected rule/set, or inject an API failure with mocks. | E; inspect manifest; P must not proceed on incomplete discovery. | Failed export is explicit and incomplete, never promoted as authoritative state. |
| E06 - Existing export destination | Export twice to the same test output root; decline replacement, then separately approve after backup. | Use the export command with a fixed test destination; compare snapshot contents. | Decline preserves files; approval replaces only that export destination. |
| E07 - Stable filenames across environments | Export the same eligible set under two environment names into different roots. | E twice; compare relative authoring paths and internal target keys. | Assignment filename has no environment prefix; internal names/targets remain environment-aware. |

## 11. Output, enforcement, and final recovery

| Test / what it accomplishes | Setup instructions | Run instructions | Expected result |
|---|---|---|---|
| U01 - Display versus machine identity | Use workspace-valued parameter additions/removals and capacity changes. | P/R; compare console names to saved GUID values; V. | Human-readable names in output; saved plan/API IDs unchanged; unknown display references remain identifiable. |
| U02 - Deployment hierarchy and truthful results | Apply policy-only, metadata-only, mixed, and adoption cases separately. Inject a write failure with mocks. | D/E, or mocked failure test; inspect ordering and colors. | Set context precedes indented child results; no redundant trailing set-update line; failed writes are never reported as completed. |
| U03 - Allowed and blocked operations | On an approved active matrix rule, choose one allowed workspace/item combination and one blocked combination. Use a non-admin test principal subject to enforcement. | Wait for propagation (up to 15 minutes), perform both actions, capture API/portal results; remove only items created by the probe. | Allowed operation succeeds; blocked operation fails for policy reasons. An accepted configuration call alone is insufficient. |
| U04 - Deactivation enforcement | Record U03 results; deactivate the test rule/set with approval while ensuring no other policy independently blocks the same operation. | D/E; wait for propagation; repeat the formerly blocked probe; restore original enforcement. | Observed behavior tracks activation state, not an unrelated permission or policy. |
| U05 - Final cleanup and baseline | Follow the cleanup sequence below, retaining the matrix owner until its resources are removed; handle unowned portal fixtures separately. | P/R/V/D on the approved boundary; read back; Z for retained baseline. | No unexpected deletes; no matrix resources or active test enforcement remain; baseline sets and B sentinel remain as intended. |
| U06 - Concise deletion and inactive status output | Prepare a disposable set deletion; separately change rules without changing set status. | P with/without `-DetailedOutput`; R/V; approved D. | Deleted set is a concise named deletion, not a dump of its contents; unchanged activation bookkeeping is hidden from human change output but retained where needed in saved plans. |

## Combination coverage

Execute these combinations explicitly rather than assuming individual rows
prove them:

| Dimensions | Minimum combinations |
|---|---|
| Reuse | One policy -> two sets; one set -> two assignments; one assignment -> two children -> different scopes/values; one child -> multiple targets with shared values; multiple children -> multiple targets. |
| Lifecycle | Create, parameter update, rule rename, set rename, rule removal, storage replacement, set deletion; follow every successful operation with read-back and Z. |
| Scope/status | Inactive A/B drafts; one active A and one active B; competing active A; tenant-only; inclusive tenant; invalid active unbound draft. |
| Ownership/strategy | OwnedOnly/Full x declared/omitted x run-owned/unowned/foreign-owned. Keep foreign-owner and broad-Full danger cases mocked until an explicit safety policy and isolated boundary exist. |
| Parameters | Workspace names/IDs; capacity names/IDs; one/many/empty array values; required/missing/unknown value; independent shared consumers; changed metadata target. |
| Deployment mode | Preview/confirmed/unattended x ordinary/adoption/activation replacement; declined confirmation; failure after earlier successful writes. |
| Authoring format | JSONC comments/trailing commas in all folders; mixed legacy JSON; duplicate identity across extensions; schema versus runtime diagnostics. |

For each shared-consumer test, capture **all consumers**, not only the edited
one. Assert unchanged values, item IDs, rule IDs, status, and scope for siblings.
For fan-out cardinality changes, compare the surviving targets' identities before
and after; matching final counts alone do not prove correct behavior.

## Implementation-sensitive checks

These are reasons to run tests, not waivers that turn a failed expectation into
a pass:

1. **Per-target values:** target-level parameters are not supported. Use
   children/separate assignments and complete child parameter maps.
2. **Schema versus runtime validation:** authoring schemas are not automatically
   applied in full by P. Keep schema rejection and runtime rejection results
   separate; invalid input reaching deployment is a validation gap.
3. **Stable identities with reuse:** explicit template `metadata.fpacId` can be
   copied into multiple materialized instances, and ownership alignment rejects
   ambiguous owner/ID matches. Test rename/replacement after reuse, not only
   initial creation. Expanding a single target into several also changes how
   instance names are generated; check for unintended identity churn.
4. **Shared-policy export:** the exporter currently rejects an already-existing
   policy-definition filename. Multiple live sets sharing one stable policy ID
   need an explicit completeness/deduplication test.
5. **Effect updates:** ordinary rule PATCH currently sends display name,
   description, and conditions, not effects. P12 must prove actual convergence
   or record the unsupported update path.
6. **Full and foreign owners:** matching foreign-owned sets are protected during
   planning/adoption/update, but omitted-set deletion under Full does not have
   the same owner exemption. Do not use a live destructive test to discover
   this boundary in a shared tenant.
7. **Stale plans:** current checks cover settings, boundaries, target existence,
   ownership on update/adoption, and expected active-set identity. They do not
   constitute a full snapshot lock on every rule, status, scope, or delete target.
8. **Cross-environment aliases:** the active-scope guard compares declared
   capacity keys before full cross-environment name/ID normalization. Test
   alternate encodings for the same capacity without deploying a conflict.
9. **Inactive bindings:** Fabric may report an inactive capacity set as unbound.
   Do not waive repeated scope differences as cosmetic until persistence and
   zero-drift behavior are understood.
10. **Child defaults:** expansion can fall back from child status to root status,
    while cross-environment active-scope checks treat an omitted child status as
    Active. Explicit child statuses avoid this disagreement; A16 tests it.

## Cleanup and recovery

1. Stop testing after an unexpected write. Preserve the reviewed plan, accepted
   operations, error output, and fresh read-back before retrying anything.
   Deployment is not transactional; do not assume an automatic rollback.
2. With the administrator, restore the previously active set on each affected
   scope from the pre-test record. Deactivate matrix enforcement before removing
   probe items. Do not activate a guessed replacement.
3. Keep the unique matrix `pacOwnerId` and `OwnedOnly`. Move the run's assignment
   files outside the active definitions tree. Do **not** switch back to the
   original owner first: otherwise the matrix resources will no longer be
   selected as that owner's omitted resources.
4. Use P/R/V/D under `Matrix-AB` to remove the run's disposable A/B sets; use
   `Matrix-Tenant` separately if tenant fixtures were created. Verify that every
   proposed deletion has the matrix owner and a recorded test item ID. Retain
   assignments for any matrix-owned sentinel intentionally kept. Do not use
   Full to simplify cleanup.
5. Delete only explicitly recorded unowned/foreign-owner portal fixtures and
   probe items through an approved manual process. Never treat a prefix search
   as permission to delete every matching resource.
6. Read back all affected scopes and baseline sets. Restore the original working
   settings/definitions only after matrix cleanup, then run P twice against
   that original baseline without re-exporting over it. Record residual drift
   or an intentionally retained sentinel explicitly. Keep local evidence until
   results are reviewed.

## Automated coverage and evidence

This is a PowerShell CLI/Fabric API test plan, not a web-app startup or container
test plan. Live tests need the real Fabric service; mocked Pester tests cover
faults and dangerous permutations without changing cloud state. Portal steps
are manual and enforcement tests exercise real Fabric operations.

Reuse the existing [Pester suites](https://github.com/Azure/fabric-policy-as-code/tree/main/tests) and add regression tests for defects
found here. They cover authoring/parsing, export/planning, deployment,
ownership, boundaries, and display behavior; passing mocks are not proof of live
API compatibility or enforcement. Run the existing CI-style baseline before
and after a testing/fix batch:

```powershell
Import-Module Pester -RequiredVersion 5.7.1
$configuration = New-PesterConfiguration
$configuration.Run.Path = Join-Path $repo 'tests'
$configuration.Run.PassThru = $true
$configuration.Output.Verbosity = 'Normal'
$result = Invoke-Pester -Configuration $configuration
if ($result.FailedCount -gt 0 -or $result.PassedCount -eq 0 -or $result.NotRunCount -gt 0) {
    throw 'Pester did not complete successfully.'
}
```

For each case, record the commit/worktree version, test owner, selected
environment, identities/permissions, exact commands and approval flags,
timestamps, exit/failure results, reviewed plan, before/after reads, and final
zero-drift outcome. Store raw evidence under the ignored run directory; redact
tenant/customer information before sharing and never record access tokens.

| Test ID | Result | Commit/worktree | Environment | Evidence location | Cleanup/Z | Defect or notes |
|---|---|---|---|---|---|---|
| Example: A05 | Not run | Record before execution | Matrix-AB | `evidence\A05-*` | Not run | No execution implied by this document |

Use **Pass**, **Fail**, **Blocked**, or **Not run**. A blocked permission/API case
is not a pass. A nonzero command result, incorrect sibling change, or persistent
post-deployment drift fails the relevant case. Preserve partial-failure evidence
before recovery. Do not mark an entire category passed from one successful row.

The core release gate is: supported reuse/fan-out permutations converge,
boundaries and approval checks hold, failed writes remain explicit, and
allowed/blocked enforcement is demonstrated on disposable resources. Any failed
Verify case needs a tracked defect or an explicitly documented unsupported
scenario before claiming that capability.
