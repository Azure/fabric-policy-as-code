# PowerShell module

## Install

Use PowerShell 7.4 or newer. After a release has been published:

```powershell
Install-Module FabricPolicyAsCode -RequiredVersion 0.1.0 -Scope CurrentUser
Import-Module FabricPolicyAsCode -RequiredVersion 0.1.0
Get-Command -Module FabricPolicyAsCode
```

`Az.Accounts` 5.0.1 or later is a required dependency. Pin the FPAC version in
automation; do not silently take the latest package at deployment time.
Before the first release, use the local build instructions below.

## Commands

| Command | Purpose | Result |
|---|---|---|
| `Export-FpacPolicy` | Export visible live configuration | Definitions, assignments, and manifest on disk |
| `New-FpacPolicyPlan` | Compare desired and live state without changing Fabric | Object with `Plan`, `PlanFile`, `PolicyStage`, `InformationLog` |
| `Invoke-FpacPolicyDeployment` | Apply an approved plan | Operation counts; supports `-WhatIf` and `-Confirm` |

Paths default to `Definitions` and `Output` under the caller's current directory,
not the installation directory. `-GlobalSettingsPath` defaults to
`Definitions\global-settings.jsonc`. Select an environment explicitly in
automation. All commands support `-MaxRetryAttempts` (1-10, default 5).

Planning also supports `-DefinitionsPath`, `-OutputPath`, and `-DetailedOutput`.
Deployment accepts `-PlanFile`, or resolves a plan under
`Output\plans-<environment>\policy-plan.json`. Its operation timeout defaults to
1,800 seconds (`-OperationTimeoutSeconds`, 1-7,200). Adoption and activation
replacement remain opt-in with `-AdoptUnowned` and
`-AllowActivationReplacement`.

```powershell
Connect-AzAccount -Tenant '<tenant-id>'
Export-FpacPolicy -EnvironmentName Development

# Promote reviewed exported artifacts into Definitions before planning.
$result = New-FpacPolicyPlan -EnvironmentName Development -DetailedOutput
if ($result.PolicyStage -eq 'yes') {
    Invoke-FpacPolicyDeployment -PlanFile $result.PlanFile -WhatIf
    # Review the saved plan before explicitly approving real changes:
    Invoke-FpacPolicyDeployment -PlanFile $result.PlanFile -Confirm:$false
}
```

When no changes exist, `PolicyStage` is `no`, `PlanFile` is null, and no plan
file is retained. The module does not turn an incomplete discovery into a
deployable plan. Deployment preserves the existing schema, ownership, tenant,
scope, stale-state, adoption, and activation safeguards.

Authentication uses the current Az.Accounts context and a token for
`https://api.fabric.microsoft.com`. Interactive login is available locally;
CI without an existing context fails rather than prompting.

## Build and consume locally

From the repository root:

```powershell
$package = .\Module\build.ps1
Test-ModuleManifest (Join-Path $package 'FabricPolicyAsCode.psd1')
Import-Module (Join-Path $package 'FabricPolicyAsCode.psd1') -Force
```

The package is staged under `.build\module\FabricPolicyAsCode\0.1.0`. A repeated
build refuses to overwrite an existing version; select a fresh `-OutputPath`.
To install without Gallery, copy the versioned `FabricPolicyAsCode` directory
into a directory on `$env:PSModulePath`, or import the manifest by absolute path.

The package contains only the module, public commands, shared helpers, schemas,
license, and README. It does not contain local definitions, generated plans,
tests, or credentials. Existing source script entry points remain available;
both surfaces call the same shared operation functions.

Use `Get-Help <command> -Full` for examples, and the
[configuration reference](../README.md) for source-script usage.
