# FPAC implementation and validation roadmap

This guide describes how to take FPAC from its initial public source baseline to a
validated, documented, packaged, and automated open-source project. It includes
the order of work, detailed setup instructions, example GitHub Actions workflows,
repository rules, the Fabric test environment, and the end-to-end validation
matrix.

FPAC and the Microsoft Fabric policy APIs are currently early-stage or preview
technology. Use dedicated nonproduction capacities and workspaces. Do not use the
first FPAC deployment against production resources.

## Recommended order

Complete the work in this order:

1. Harden the GitHub repository and add pull-request validation.
2. Create the isolated Microsoft Fabric test environment.
3. Complete the manual export, plan, approval, deployment, and zero-drift cycle.
4. Complete update, replacement, deletion, conflict, and failure testing.
5. Stabilize and package the PowerShell module.
6. Build the documentation site.
7. Add documentation and module publishing.
8. Add the OIDC-authenticated plan and approval-gated deployment workflow.

Do not automate a deployment behavior that has not first succeeded manually
against the live Fabric APIs.

## Current baseline

The initial FPAC implementation is on the `main` branch of:

<https://github.com/Azure/fabric-policy-as-code>

The baseline contains:

- Export, deployment-plan, and deployment scripts.
- JSON schemas for settings, assignments, policy definitions, policy sets, and
  deployment plans.
- Pester tests for export, planning, deployment, ownership, environment
  isolation, authentication, retries, and failure cases.
- 54 passing tests at the time the initial implementation was merged.

The repository intentionally ignores:

- `Definitions/`, because the local copy contains tenant-specific desired state.
- `Definitionsold/`, because it contains legacy local examples.
- `Output/`, because it contains generated exports and deployment plans.

Public examples should eventually be stored under a sanitized `examples/`
directory rather than under the operator's live `Definitions/` directory.

---

# Phase 1: Repository hardening

## 1. Synchronize the local repository

Start each unit of work from the current upstream `main` branch:

```powershell
Set-Location C:\Users\gregslack\Repos\FPAC
git fetch origin
git switch main
git pull --ff-only origin main
```

Create a branch for repository hardening:

```powershell
git switch -c repository-hardening
```

Do not continue work on a branch after its pull request has been merged.

## 2. Add repository governance files

Create these files at the repository root:

| File | Purpose |
| --- | --- |
| `SECURITY.md` | Defines supported versions and private vulnerability reporting. |
| `CONTRIBUTING.md` | Explains setup, testing, pull requests, and contribution expectations. |
| `CODE_OF_CONDUCT.md` | Defines the community behavior standard. |
| `.github/CODEOWNERS` | Assigns default reviewers and maintainers. |
| `.github/pull_request_template.md` | Prompts contributors for changes and validation evidence. |

Follow the Azure organization requirements for security reporting and community
standards. Do not invent a security mailbox or Microsoft alias. Obtain the
approved contact from the repository sponsor or Azure open-source onboarding
process.

A starting `CODEOWNERS` file can be:

```text
# Replace or extend this list when additional maintainers join.
* @gregslack78

/.github/ @gregslack78
/docs/ @gregslack78
/schemas/ @gregslack78
/scripts/ @gregslack78
/tests/ @gregslack78
```

A pull-request template can start with:

```markdown
## Summary

Describe the user-visible or engineering change.

## Validation

- [ ] Relevant Pester tests pass.
- [ ] New behavior has automated coverage.
- [ ] Documentation is updated when behavior or configuration changed.
- [ ] No tenant IDs, credentials, tokens, customer data, or generated output are included.

## Deployment impact

Describe any effect on planning, ownership, adoption, activation, replacement,
or deletion.
```

## 3. Create the pull-request validation workflow

Create:

```text
.github/workflows/pr-validation.yml
```

Use this initial workflow:

```yaml
name: PR Validation

on:
  pull_request:
    branches:
      - main
  push:
    branches:
      - main
  workflow_dispatch:

permissions:
  contents: read

concurrency:
  group: pr-validation-${{ github.ref }}
  cancel-in-progress: true

jobs:
  pester:
    name: Pester
    runs-on: windows-latest
    timeout-minutes: 15

    steps:
      - name: Checkout
        uses: actions/checkout@v4

      - name: Install Pester
        shell: pwsh
        run: |
          $ErrorActionPreference = 'Stop'
          Install-Module Pester `
            -RequiredVersion 5.7.1 `
            -Scope CurrentUser `
            -Force `
            -SkipPublisherCheck

      - name: Run tests
        shell: pwsh
        run: |
          $ErrorActionPreference = 'Stop'

          $configuration = New-PesterConfiguration
          $configuration.Run.Path = './tests'
          $configuration.Run.PassThru = $true
          $configuration.Output.Verbosity = 'Detailed'
          $configuration.TestResult.Enabled = $true
          $configuration.TestResult.OutputFormat = 'NUnitXml'
          $configuration.TestResult.OutputPath = 'TestResults.xml'

          $result = Invoke-Pester -Configuration $configuration
          if ($result.FailedCount -gt 0) {
              throw "$($result.FailedCount) Pester test(s) failed."
          }

      - name: Upload test results
        if: always()
        uses: actions/upload-artifact@v4
        with:
          name: pester-results
          path: TestResults.xml
          if-no-files-found: error
          retention-days: 14
```

### Why start with Windows only

The current implementation and manual validation have primarily used Windows
PowerShell 7. Start with one deterministic CI environment. After the suite is
passing consistently under Pester 5, add `ubuntu-latest` to verify that file
paths, case sensitivity, and PowerShell behavior are portable.

Do not add an operating-system matrix merely to make the workflow look
comprehensive. Add each runner only after failures on that runner will be treated
as release blockers.

### Validate the workflow before making it required

Commit and push the workflow:

```powershell
git add .github SECURITY.md CONTRIBUTING.md CODE_OF_CONDUCT.md
git diff --cached --check
git commit -m "Add repository governance and PR validation"
git push -u fork repository-hardening
```

Open a pull request:

```powershell
gh pr create `
  --repo Azure/fabric-policy-as-code `
  --base main `
  --head gregslack78:repository-hardening `
  --title "Add repository governance and PR validation" `
  --body "Adds the initial Pester validation workflow and public repository governance files."
```

Wait for the workflow to run. Confirm that the check shown on the pull request is
named:

```text
PR Validation / Pester
```

If Pester 5 exposes compatibility issues, fix the tests or implementation before
making the check mandatory. Do not change CI to the older preinstalled Pester
version merely to obtain a green result.

References:

- [Building and testing PowerShell with GitHub Actions](https://docs.github.com/en/actions/tutorials/build-and-test-code/powershell)
- [Pester test-result configuration](https://pester.dev/docs/usage/test-results)

## 4. Create the `main` branch ruleset

The workflow must run at least once before its status check can reliably be
selected in repository rules.

To create the ruleset:

1. Open <https://github.com/Azure/fabric-policy-as-code>.
2. Select **Settings**.
3. In the left navigation, select **Rules** > **Rulesets**.
4. Select **New ruleset** > **New branch ruleset**.
5. Set **Ruleset name** to `Protect main`.
6. Set **Enforcement status** to **Active**.
7. Under **Target branches**, select **Add target** > **Include default branch**.
8. Do not add a bypass actor for routine development.
9. Configure the rules below.

Enable:

- **Restrict deletions**
- **Block force pushes**
- **Require a pull request before merging**
- **Require status checks to pass**
- **Require branches to be up to date before merging**
- **Require conversation resolution before merging**

Under required status checks, add:

```text
PR Validation / Pester
license/cla
```

The CLA check name is supplied by the Microsoft GitHub Policy Service. Select the
actual check name shown on a recent pull request rather than typing an assumed
name.

### Approval count while there is only one maintainer

If the repository has only one active maintainer, set required approving reviews
to `0` initially. Requiring one approval while only the author can maintain the
project can deadlock routine work.

After a second maintainer or owning GitHub team is established:

1. Change required approvals to `1`.
2. Enable **Require review from Code Owners**.
3. Enable dismissal of stale approvals when significant changes are pushed.
4. Enable **Prevent self-review** for deployments.

### Rules not recommended initially

Do not initially require:

- Signed commits, until the contributor and bot signing experience is confirmed.
- Linear history, until the repository selects squash/rebase as its standard
  merge method.
- A deployment to succeed before merge, because live Fabric deployment must not
  run for untrusted pull requests.

Select **Create** to activate the ruleset.

Reference:

- [Creating repository rulesets](https://docs.github.com/en/repositories/configuring-branches-and-merges-in-your-repository/managing-rulesets/creating-rulesets-for-a-repository)

## 5. Configure general repository settings

Under **Settings** > **General**:

1. Confirm `main` is the default branch.
2. Enable **Automatically delete head branches**.
3. Enable squash merging.
4. Decide whether merge commits will remain allowed.
5. Disable rebase merging if the project wants one consistent merge strategy.
6. Keep Issues enabled.
7. Add the repository description and project website when the documentation site
   is published.

Recommended description:

```text
Fabric Policy as Code: export, plan, review, and deploy Microsoft Fabric governance policies.
```

Recommended topics:

```text
microsoft-fabric
policy-as-code
governance
powershell
devops
github-actions
```

## Phase 1 completion criteria

Phase 1 is complete when:

- Pull requests run Pester automatically.
- The current test suite passes under the CI Pester version.
- `main` cannot be force-pushed or deleted.
- Merges require the Pester and CLA checks.
- Security and contribution instructions are public.
- Tenant-specific definitions and generated output remain untracked.

---

# Phase 2: Create the Fabric test environment

## 1. Resource layout

Use a dedicated Azure resource group:

```text
rg-fpac-test
```

Create two small pay-as-you-go F SKU capacities:

| Capacity | Purpose |
| --- | --- |
| `fpac-test-cap-a` | Primary governance and ordinary lifecycle testing |
| `fpac-test-cap-b` | Multi-capacity, fan-out, isolation, and replacement testing |

Start with F2 if it is available in the selected region and supports the required
Fabric policy preview. Verify subscription quota and regional availability before
creation. Place both capacities in the same region unless regional differences
are explicitly under test.

Pause both capacities whenever they are not in use. Pausing stops normal capacity
billing, although accumulated usage and overages can still affect billing.

Reference:

- [Pause and resume a Fabric capacity](https://learn.microsoft.com/fabric/enterprise/pause-resume)

## 2. Create the capacities in Azure

For each capacity:

1. Sign in to <https://portal.azure.com/>.
2. Search for **Microsoft Fabric**.
3. Select **Create Fabric capacity**.
4. Select the test subscription.
5. Create or select `rg-fpac-test`.
6. Enter `fpac-test-cap-a` for the first capacity.
7. Select the approved region.
8. Set the capacity administrator to the interactive test operator or an
   approved administration group.
9. Select the F2 SKU if available and approved.
10. Review and create the capacity.
11. Repeat for `fpac-test-cap-b`.

Record:

- Subscription.
- Resource group.
- Region.
- SKU.
- Capacity administrators.
- Expected hourly cost.
- The owner responsible for pausing the capacity.

Do not put access tokens, credentials, or billing data in the public repository.

## 3. Create the workspaces

Create these nonproduction workspaces in the Fabric portal:

| Workspace | Capacity | Purpose |
| --- | --- | --- |
| `FPAC-Governance-A` | `fpac-test-cap-a` | Primary Policy Set storage |
| `FPAC-App-A1` | `fpac-test-cap-a` | First governed workload workspace |
| `FPAC-App-A2` | `fpac-test-cap-a` | Multi-workspace fan-out |
| `FPAC-Governance-B` | `fpac-test-cap-b` | Secondary storage and replacement |
| `FPAC-App-B1` | `fpac-test-cap-b` | Cross-capacity target |
| `FPAC-Negative-Unassigned` | No capacity | Negative test for unassigned workspaces |

To create and assign a workspace:

1. Open <https://app.fabric.microsoft.com/>.
2. Select **Workspaces** > **New workspace**.
3. Enter the workspace name.
4. Create the workspace.
5. Open **Workspace settings**.
6. Open the capacity or license section.
7. Assign the workspace to the intended Fabric capacity.
8. Give the interactive test operator the **Admin** workspace role.

Leave `FPAC-Negative-Unassigned` outside both test capacities. It must never be
used for a real deployment; it exists only to confirm that planning rejects an
unassigned target.

## 4. Enable Fabric Policies

Follow [Fabric setup and manually creating a policy](fabric-setup-and-create-policy.md)
to:

- Enable the Policies preview tenant setting.
- Confirm any capacity-level delegated settings.
- Confirm workspace roles.
- Confirm capacity-administrator rights.
- Confirm that **New item** > **Policy set** is available.

Start with capacity-scoped policies. Test tenant scope only after all
capacity-scoped tests have passed.

## 5. Configure the local FPAC environments

Update the ignored local file:

```text
Definitions/global-settings.jsonc
```

Use:

```jsonc
{
  "$schema": "../schemas/global-settings.schema.json",
  "pacOwnerId": "gregslack-fpac-test",
  "desiredStateStrategy": "OwnedOnly",
  "environments": [
    {
      "name": "TestCapacityA",
      "tenantId": "<tenant-guid>",
      "scope": [
        {
          "name": "fpac-test-cap-a"
        }
      ]
    },
    {
      "name": "TestCapacityB",
      "tenantId": "<tenant-guid>",
      "scope": [
        {
          "name": "fpac-test-cap-b"
        }
      ]
    },
    {
      "name": "TestAllCapacities",
      "tenantId": "<tenant-guid>",
      "scope": [
        {
          "name": "fpac-test-cap-a"
        },
        {
          "name": "fpac-test-cap-b"
        }
      ]
    },
    {
      "name": "TestTenant",
      "tenantId": "<tenant-guid>",
      "scope": [
        {
          "type": "Tenant"
        }
      ]
    }
  ]
}
```

Replace `<tenant-guid>` locally. Never commit the operator's tenant-specific
settings to the public repository.

## Phase 2 completion criteria

Phase 2 is complete when:

- Both capacities can be resumed and paused.
- All five capacity-backed workspaces are accessible.
- The negative workspace remains unassigned.
- Policy Set creation is available in `FPAC-Governance-A`.
- The operator can activate a capacity-scoped policy.
- FPAC can obtain a Fabric token for the target tenant.

---

# Phase 3: Manual end-to-end validation

## 1. Create the initial unowned Policy Set

In `FPAC-Governance-A`, create:

```text
Policy Set: FPAC E2E Capacity A
Administrative scope: fpac-test-cap-a
Initial state: Active
```

Create two low-risk `ItemCreation` rules.

### Rule 1: Allowed workspaces

```text
Display name: FPAC E2E Allowed Workspaces
Target property: workspace.id
Operator: AnyOf
Values:
  - FPAC-App-A1
  - FPAC-App-A2
Effect: Allow
```

### Rule 2: Allowed item types

```text
Display name: FPAC E2E Allowed Item Types
Target property: item.type
Operator: AnyOf
Effect: Allow
```

Choose two harmless item types offered by the Fabric Policies UI. Use the values
returned by Fabric; do not guess internal item-type identifiers.

This Policy Set is intentionally created outside FPAC so the first deployment can
validate explicit adoption.

## 2. Authenticate interactively

From PowerShell 7.4 or later:

```powershell
Install-Module Az.Accounts -Scope CurrentUser
Connect-AzAccount -Tenant '<tenant-guid>'
Get-AzContext
```

Confirm the active tenant matches `Definitions/global-settings.jsonc`.

## 3. Export the live policy

From the repository root:

```powershell
.\scripts\operations\Export-PolicyToFPAC.ps1 `
  -EnvironmentName 'TestCapacityA' `
  -OutputPath '.\Output'
```

Inspect:

```text
Output/TestCapacityA/
  assignments/
  policyDefinitions/
  policySets/
  manifest.json
```

Confirm:

- The manifest reports a complete export.
- The Policy Set appears once.
- Both rules are exported.
- Workspace and capacity references are portable names where FPAC can resolve
  them uniquely.
- Fabric item IDs and timestamps are not treated as desired state.

If the manifest reports failures, stop. Do not promote an incomplete export into
desired state.

## 4. Promote the export into local desired state

Create the folders if they do not exist:

```powershell
New-Item -ItemType Directory -Force -Path `
  '.\Definitions\assignments', `
  '.\Definitions\policyDefinitions', `
  '.\Definitions\policySets' | Out-Null
```

Copy the exported objects:

```powershell
Copy-Item '.\Output\TestCapacityA\assignments\*' `
  '.\Definitions\assignments' -Force

Copy-Item '.\Output\TestCapacityA\policyDefinitions\*' `
  '.\Definitions\policyDefinitions' -Force

Copy-Item '.\Output\TestCapacityA\policySets\*' `
  '.\Definitions\policySets' -Force
```

Review every copied file. Confirm that the target environment name and capacity
name are correct.

## 5. Build and review the adoption plan

Run:

```powershell
.\scripts\Deploy\Build-DeploymentPlans.ps1 `
  -EnvironmentName 'TestCapacityA' `
  -DetailedOutput
```

Review:

```text
Output/plans-TestCapacityA/policy-plan.json
```

The matching manually created resource should be classified as `adopt`, not
`new`, `update`, or `replace`.

Before performing adoption, run deployment in WhatIf mode:

```powershell
.\scripts\Deploy\Deploy-Policy.ps1 `
  -EnvironmentName 'TestCapacityA' `
  -AdoptUnowned `
  -WhatIf
```

Then confirm that deployment without `-AdoptUnowned` refuses to adopt the
resource:

```powershell
.\scripts\Deploy\Deploy-Policy.ps1 `
  -EnvironmentName 'TestCapacityA' `
  -Confirm:$false
```

The refusal is expected and is part of the test.

## 6. Adopt the resource

After reviewing the plan:

```powershell
.\scripts\Deploy\Deploy-Policy.ps1 `
  -EnvironmentName 'TestCapacityA' `
  -AdoptUnowned `
  -Confirm:$false
```

Confirm in Fabric that:

- The Policy Set remains present.
- Its human description remains intact.
- FPAC ownership metadata is present.
- The rules and activation state remain correct.

## 7. Prove zero drift

Build the plan again:

```powershell
.\scripts\Deploy\Build-DeploymentPlans.ps1 `
  -EnvironmentName 'TestCapacityA' `
  -DetailedOutput
```

Expected result:

- No changes are proposed.
- A stale plan from the preceding deployment does not remain.

This completes the critical lifecycle:

```text
Fabric
  -> export
  -> desired state
  -> plan
  -> explicit adoption
  -> deployment
  -> zero drift
```

## 8. Complete the lifecycle matrix

### Update

1. Change a display name, description, workspace list, or allowed item type in
   desired state.
2. Build the plan.
3. Confirm the action is `update`.
4. Deploy.
5. Export again.
6. Rebuild the plan and confirm zero drift.

### Status transition

1. Change the assignment status from `Active` to `Inactive`.
2. Plan and deploy.
3. Confirm the live set is inactive.
4. Change it back to `Active`.
5. Plan and deploy again.

### Multi-workspace fan-out

Target both `FPAC-App-A1` and `FPAC-App-A2`. Confirm that each concrete target is
materialized correctly and that workspace names resolve case-insensitively.

### Cross-capacity fan-out

Use `TestAllCapacities` to target:

- `FPAC-App-A1` on `fpac-test-cap-a`.
- `FPAC-App-B1` on `fpac-test-cap-b`.

Confirm environment boundaries and capacity assignment checks.

### Replacement

Change the storage workspace or another property that requires replacement.
Confirm the plan reports `replace`. Deployment of an active replacement may
require:

```powershell
-AllowActivationReplacement
```

Use that switch only after reviewing the replacement section of the plan.

### Owned deletion

1. Remove an FPAC-owned assignment from desired state.
2. Build the plan.
3. Confirm the action is `delete`.
4. Confirm an unrelated unowned Policy Set is absent from the deletion plan.
5. Deploy and verify only the owned resource is removed.

### Stale-plan protection

1. Build a plan.
2. Change the live Policy Set manually before deployment.
3. Attempt deployment.
4. Confirm FPAC refuses to deploy because the live activation or resource state
   no longer matches the state used during planning.

### Negative cases

Run each case separately and capture the error:

| Case | Expected result |
| --- | --- |
| Capacity name does not exist | Planning fails without guessing. |
| Workspace name does not exist | Planning fails. |
| Workspace is inaccessible | Planning fails. |
| Workspace is not assigned to a capacity | Planning fails. |
| Required policy parameter is missing | Materialization fails. |
| Tenant and capacity scopes are mixed | Settings validation fails. |
| More than one desired active set targets a scope | Planning fails. |
| Active scopes conflict across environments | Planning fails. |
| Resource is owned by another PAC owner | Deployment does not silently modify it. |
| Matching resource is unowned | Explicit adoption is required. |

### Tenant scope

Test tenant scope last:

1. Create a narrow, harmless tenant-scoped Policy Set.
2. Export with `TestTenant`.
3. Build and review the plan.
4. Confirm a Fabric administrator performs activation.
5. Deactivate or remove the test immediately after validation.

## 9. Record evidence

Create a tracking issue with this table:

| Scenario | Plan result | Deployment result | Zero drift | Evidence | Defect |
| --- | --- | --- | --- | --- | --- |
| Export |  |  | N/A |  |  |
| Adopt |  |  |  |  |  |
| Update |  |  |  |  |  |
| Inactivate/reactivate |  |  |  |  |  |
| Fan-out |  |  |  |  |  |
| Cross-capacity |  |  |  |  |  |
| Replace |  |  |  |  |  |
| Delete |  |  |  |  |  |
| Stale plan |  | Rejected | N/A |  |  |
| Negative validation |  | Rejected | N/A |  |  |
| Tenant scope |  |  |  |  |  |

Do not attach access tokens, complete authentication logs, tenant-sensitive
exports, or customer data to a public issue.

## Phase 3 completion criteria

Live validation is complete when:

- Export completes without unexplained manifest failures.
- Adoption requires explicit authorization.
- Update, replacement, deletion, and unchanged classification are correct.
- A deployment followed by planning produces zero drift.
- Stale plans are rejected.
- `OwnedOnly` preserves unrelated unowned resources.
- Both capacities remain isolated.
- Every discovered product defect has a regression test.

---

# Phase 4: Package FPAC as a PowerShell module

Do this only after live behavior is stable.

## Proposed module layout

```text
Module/
  build.ps1
  FabricPolicyAsCode/
    FabricPolicyAsCode.psd1
    FabricPolicyAsCode.psm1
    Public/
      Export-FpacPolicy.ps1
      Build-FpacDeploymentPlan.ps1
      Deploy-FpacPolicyPlan.ps1
    Private/
      <helper functions>
```

The final module name and public commands must be selected before publishing.
Avoid publishing one set of command names and renaming them immediately.

The existing scripts can remain as compatibility wrappers:

```text
scripts/operations/Export-PolicyToFPAC.ps1
scripts/Deploy/Build-DeploymentPlans.ps1
scripts/Deploy/Deploy-Policy.ps1
```

Each wrapper should import the module and call one public command. Core behavior
should not be duplicated between scripts and the module.

## Manifest requirements

The module manifest should define:

- `RootModule`
- `ModuleVersion`
- `GUID`
- `Author`
- `CompanyName`
- `Copyright`
- `Description`
- `PowerShellVersion = '7.4'`
- Required modules, including `Az.Accounts`
- Explicit `FunctionsToExport`
- Project URI
- License URI
- Release notes
- Appropriate PowerShell Gallery tags

## Module validation

At minimum, CI must:

```powershell
Test-ModuleManifest .\Module\FabricPolicyAsCode\FabricPolicyAsCode.psd1
Import-Module .\Module\FabricPolicyAsCode\FabricPolicyAsCode.psd1 -Force
Get-Command -Module FabricPolicyAsCode
Invoke-Pester -Path .\tests
```

Build the publishable module into a clean staging directory. Never publish
directly from a working source directory containing tests, local definitions, or
generated output.

## Phase 4 completion criteria

- Public commands and parameter names are stable.
- Script wrappers and module commands produce the same behavior.
- The module imports in a clean PowerShell 7.4 session.
- The manifest passes validation.
- Module tests run from the staged package.
- Versioning and release-note conventions are documented.

---

# Phase 5: Build the documentation site

Use MkDocs Material, following the general model used by EPAC:

<https://azure.github.io/enterprise-azure-policy-as-code/>

## 1. Add the documentation dependencies

Create `requirements-docs.txt`:

```text
mkdocs==1.6.1
mkdocs-material==9.6.20
```

Review and update pinned versions deliberately. Do not use an unconstrained
`pip install mkdocs mkdocs-material` in the release workflow.

## 2. Add `mkdocs.yml`

Create:

```yaml
site_name: Fabric Policy as Code
site_url: https://azure.github.io/fabric-policy-as-code/
repo_url: https://github.com/Azure/fabric-policy-as-code
docs_dir: docs

theme:
  name: material
  features:
    - navigation.instant
    - navigation.sections
    - navigation.tabs
    - navigation.tabs.sticky
    - content.code.copy

nav:
  - Home: index.md
  - Getting Started:
      - Fabric setup: fabric-setup-and-create-policy.md
      - Implementation and validation roadmap: implementation-and-validation-roadmap.md
  - Configuration:
      - Global settings: configuration/global-settings.md
      - Desired state: configuration/desired-state.md
  - Operations:
      - Export: operations/export.md
      - Plan: operations/plan.md
      - Deploy: operations/deploy.md
  - CI/CD:
      - GitHub Actions: cicd/github-actions.md
  - Reference:
      - PowerShell: reference/powershell.md

markdown_extensions:
  - admonition
  - pymdownx.details
  - pymdownx.superfences
```

Create every file referenced by `nav`; `mkdocs build --strict` should fail when a
navigation target or link is invalid.

## 3. Build locally

```powershell
python -m venv .venv
.\.venv\Scripts\python.exe -m pip install --upgrade pip
.\.venv\Scripts\python.exe -m pip install -r requirements-docs.txt
.\.venv\Scripts\python.exe -m mkdocs build --strict
.\.venv\Scripts\python.exe -m mkdocs serve
```

Open <http://127.0.0.1:8000/>.

## 4. Publish with GitHub Pages

In GitHub:

1. Open **Settings** > **Pages**.
2. Under **Build and deployment**, set **Source** to **GitHub Actions**.
3. Confirm the `github-pages` environment exists after the first deployment.

Create `.github/workflows/publish-docs.yml`:

```yaml
name: Publish documentation

on:
  push:
    branches:
      - main
    paths:
      - docs/**
      - mkdocs.yml
      - requirements-docs.txt
      - .github/workflows/publish-docs.yml
  workflow_dispatch:

permissions:
  contents: read
  pages: write
  id-token: write

concurrency:
  group: github-pages
  cancel-in-progress: false

jobs:
  build:
    name: Build documentation
    runs-on: ubuntu-latest

    steps:
      - name: Checkout
        uses: actions/checkout@v4

      - name: Set up Python
        uses: actions/setup-python@v5
        with:
          python-version: '3.13'
          cache: pip

      - name: Install dependencies
        run: python -m pip install -r requirements-docs.txt

      - name: Build
        run: python -m mkdocs build --strict

      - name: Configure Pages
        uses: actions/configure-pages@v5

      - name: Upload Pages artifact
        uses: actions/upload-pages-artifact@v4
        with:
          path: site

  deploy:
    name: Deploy documentation
    runs-on: ubuntu-latest
    needs: build
    environment:
      name: github-pages
      url: ${{ steps.deployment.outputs.page_url }}

    steps:
      - name: Deploy
        id: deployment
        uses: actions/deploy-pages@v4
```

Reference:

- [Using custom GitHub Pages workflows](https://docs.github.com/en/pages/getting-started-with-github-pages/using-custom-workflows-with-github-pages)

## Phase 5 completion criteria

- `mkdocs build --strict` passes locally and in CI.
- The site is published at the expected Azure GitHub Pages URL.
- The README links to the documentation site.
- Configuration, export, planning, deployment, ownership, and troubleshooting
  are documented.
- Examples contain no tenant-specific or sensitive values.

---

# Phase 6: Publish the PowerShell module

Create this only after the module package exists and passes staging tests.

## 1. Create the PowerShell Gallery secret

In GitHub:

1. Open **Settings** > **Environments**.
2. Create `powershell-gallery`.
3. Add required reviewers.
4. Disable administrator bypass if organization policy permits.
5. Add an environment secret named `PSGALLERY_API_KEY`.

Never place the API key in a repository secret if only release deployments need
it. Environment protection prevents the job from receiving the secret before
approval.

## 2. Create the release workflow

Create `.github/workflows/publish-module.yml`:

```yaml
name: Publish PowerShell module

on:
  release:
    types:
      - published
  workflow_dispatch:

permissions:
  contents: read

jobs:
  validate:
    name: Validate package
    runs-on: windows-latest

    steps:
      - name: Checkout
        uses: actions/checkout@v4

      - name: Build module
        shell: pwsh
        run: .\Module\build.ps1

      - name: Validate manifest
        shell: pwsh
        run: |
          $ErrorActionPreference = 'Stop'
          Test-ModuleManifest `
            .\artifacts\FabricPolicyAsCode\FabricPolicyAsCode.psd1

      - name: Upload module
        uses: actions/upload-artifact@v4
        with:
          name: FabricPolicyAsCode
          path: artifacts/FabricPolicyAsCode
          if-no-files-found: error

  publish:
    name: Publish package
    runs-on: windows-latest
    needs: validate
    environment: powershell-gallery

    steps:
      - name: Download module
        uses: actions/download-artifact@v4
        with:
          name: FabricPolicyAsCode
          path: artifacts/FabricPolicyAsCode

      - name: Publish
        shell: pwsh
        env:
          PSGALLERY_API_KEY: ${{ secrets.PSGALLERY_API_KEY }}
        run: |
          $ErrorActionPreference = 'Stop'
          Publish-Module `
            -Path .\artifacts\FabricPolicyAsCode `
            -NuGetApiKey $env:PSGALLERY_API_KEY `
            -Repository PSGallery
```

Before enabling publishing:

- Verify the Gallery module name is available.
- Verify the manifest version matches the GitHub release tag.
- Prevent republishing an existing version.
- Test the built artifact in a clean PowerShell process.

---

# Phase 7: Add approval-gated plan and deployment

Do not create this workflow until interactive live validation has passed and the
service principal permissions are understood.

## 1. Create the Entra application

Create one Entra application/service principal for FPAC GitHub Actions.

Use GitHub workload identity federation. Do not create a client secret.

Create a federated credential restricted to:

```text
repository:Azure/fabric-policy-as-code:environment:FPAC-TEST-PLAN
```

Create a second credential for:

```text
repository:Azure/fabric-policy-as-code:environment:FPAC-TEST-DEPLOY
```

Grant only the required Fabric access:

- Read access needed to discover capacities, workspaces, Policy Sets, and rules.
- Workspace access for the governance workspaces.
- Capacity administration required for capacity activation.
- Do not grant tenant-wide Fabric administration until tenant deployment is
  explicitly required.

Fabric policy APIs support service principals and managed identities:

- [Fabric policy-as-code REST APIs](https://learn.microsoft.com/fabric/governance/fabric-policies-rest-api)

## 2. Create GitHub environments

Open **Settings** > **Environments**.

### `FPAC-TEST-PLAN`

Configure:

- Deployment branches: selected branch `main`.
- Variables:
  - `AZURE_CLIENT_ID`
  - `AZURE_TENANT_ID`
- No required reviewer for the initial read-only planning job.

### `FPAC-TEST-DEPLOY`

Configure:

- Required reviewer: a maintainer other than the workflow initiator when a
  second maintainer is available.
- Enable **Prevent self-review** when practical.
- Deployment branches: selected branch `main`.
- Disable administrator bypass if organization policy permits.
- Variables:
  - `AZURE_CLIENT_ID`
  - `AZURE_TENANT_ID`

OIDC client and tenant IDs are identifiers, not credentials. They can be
environment variables. Do not store a client secret because none should exist.

Required reviewers create the pause between planning and deployment. The deploy
job cannot start or obtain environment secrets until approval.

Reference:

- [GitHub deployments and environments](https://docs.github.com/en/actions/reference/workflows-and-actions/deployments-and-environments)

## 3. Decide how desired state is supplied

The public FPAC product repository ignores `Definitions/`. A deployment workflow
therefore needs one of these models:

1. A separate private or customer-owned policy repository consumes the published
   FPAC module. This is the recommended production model.
2. A dedicated integration-test definitions folder with only synthetic public
   test configuration is committed to the FPAC repository.

Do not remove `Definitions/` from `.gitignore` and publish tenant-specific desired
state merely to make a workflow convenient.

The workflow below assumes a safe definitions folder is available to the
workflow and that its global settings do not disclose restricted information.

## 4. Initial plan/deploy workflow

Create `.github/workflows/fpac-deploy.yml` only after the definitions source has
been decided:

```yaml
name: FPAC plan and deploy

on:
  workflow_dispatch:
    inputs:
      environmentName:
        description: FPAC environment name
        required: true
        type: choice
        options:
          - TestCapacityA
          - TestCapacityB
          - TestAllCapacities

permissions:
  contents: read
  id-token: write

concurrency:
  group: fpac-${{ inputs.environmentName }}
  cancel-in-progress: false

env:
  DEFINITIONS_PATH: ./Definitions
  OUTPUT_PATH: ./Output

jobs:
  plan:
    name: Plan
    runs-on: windows-latest
    environment: FPAC-TEST-PLAN
    outputs:
      hasChanges: ${{ steps.detect.outputs.hasChanges }}

    steps:
      - name: Checkout
        uses: actions/checkout@v4

      - name: Azure login
        uses: azure/login@v2
        with:
          client-id: ${{ vars.AZURE_CLIENT_ID }}
          tenant-id: ${{ vars.AZURE_TENANT_ID }}
          allow-no-subscriptions: true
          enable-AzPSSession: true

      - name: Install Az.Accounts
        shell: pwsh
        run: |
          Install-Module Az.Accounts `
            -Scope CurrentUser `
            -Force `
            -Repository PSGallery

      - name: Build plan
        shell: pwsh
        run: |
          $ErrorActionPreference = 'Stop'
          .\scripts\Deploy\Build-DeploymentPlans.ps1 `
            -DefinitionsPath $env:DEFINITIONS_PATH `
            -OutputPath $env:OUTPUT_PATH `
            -EnvironmentName '${{ inputs.environmentName }}' `
            -DetailedOutput

      - name: Detect changes
        id: detect
        shell: pwsh
        run: |
          $plan = Join-Path `
            $env:OUTPUT_PATH `
            'plans-${{ inputs.environmentName }}\policy-plan.json'

          if (Test-Path -LiteralPath $plan) {
              "hasChanges=true" >> $env:GITHUB_OUTPUT
          }
          else {
              "hasChanges=false" >> $env:GITHUB_OUTPUT
              "## FPAC plan`nNo changes were detected." >> $env:GITHUB_STEP_SUMMARY
          }

      - name: Add plan to summary
        if: steps.detect.outputs.hasChanges == 'true'
        shell: pwsh
        run: |
          $plan = Join-Path `
            $env:OUTPUT_PATH `
            'plans-${{ inputs.environmentName }}\policy-plan.json'

          "## FPAC plan" >> $env:GITHUB_STEP_SUMMARY
          '```json' >> $env:GITHUB_STEP_SUMMARY
          Get-Content -LiteralPath $plan >> $env:GITHUB_STEP_SUMMARY
          '```' >> $env:GITHUB_STEP_SUMMARY

      - name: Upload immutable plan
        if: steps.detect.outputs.hasChanges == 'true'
        uses: actions/upload-artifact@v4
        with:
          name: plans-${{ inputs.environmentName }}
          path: Output/plans-${{ inputs.environmentName }}
          if-no-files-found: error
          retention-days: 7

  deploy:
    name: Deploy approved plan
    if: needs.plan.outputs.hasChanges == 'true'
    needs: plan
    runs-on: windows-latest
    environment: FPAC-TEST-DEPLOY

    steps:
      - name: Checkout
        uses: actions/checkout@v4

      - name: Download reviewed plan
        uses: actions/download-artifact@v4
        with:
          name: plans-${{ inputs.environmentName }}
          path: Output/plans-${{ inputs.environmentName }}

      - name: Azure login
        uses: azure/login@v2
        with:
          client-id: ${{ vars.AZURE_CLIENT_ID }}
          tenant-id: ${{ vars.AZURE_TENANT_ID }}
          allow-no-subscriptions: true
          enable-AzPSSession: true

      - name: Install Az.Accounts
        shell: pwsh
        run: |
          Install-Module Az.Accounts `
            -Scope CurrentUser `
            -Force `
            -Repository PSGallery

      - name: Deploy
        shell: pwsh
        run: |
          $ErrorActionPreference = 'Stop'
          .\scripts\Deploy\Deploy-Policy.ps1 `
            -EnvironmentName '${{ inputs.environmentName }}' `
            -Confirm:$false

      - name: Verify zero drift
        shell: pwsh
        run: |
          $ErrorActionPreference = 'Stop'
          .\scripts\Deploy\Build-DeploymentPlans.ps1 `
            -DefinitionsPath $env:DEFINITIONS_PATH `
            -OutputPath $env:OUTPUT_PATH `
            -EnvironmentName '${{ inputs.environmentName }}' `
            -DetailedOutput

          $plan = Join-Path `
            $env:OUTPUT_PATH `
            'plans-${{ inputs.environmentName }}\policy-plan.json'

          if (Test-Path -LiteralPath $plan) {
              throw 'FPAC detected drift immediately after deployment.'
          }
```

### Important workflow rules

- Plan and deploy must be separate jobs.
- Deployment must consume the exact uploaded plan artifact.
- The deployment job must not silently regenerate and replace the approved plan.
- The deploy environment must provide the human approval pause.
- The plan must be checked for staleness during deployment.
- Post-deployment planning must produce zero drift.
- Initial automation should use `workflow_dispatch`, not automatic deployment on
  every push.
- Adoption and activation replacement should not be enabled automatically.
  Create separately reviewed workflows or explicit inputs if those operations are
  later required.

## Phase 7 completion criteria

- GitHub authenticates with OIDC and no client secret.
- Plan can run without deployment approval.
- The deploy job waits for the protected-environment reviewer.
- Deployment consumes the reviewed plan artifact.
- Stale-plan checks remain effective.
- Post-deployment planning returns zero drift.
- Adoption and replacement remain explicit high-risk actions.

---

# Suggested milestones and issues

Create these GitHub milestones:

1. `Repository hardening`
2. `Live E2E validation`
3. `PowerShell module`
4. `Documentation site`
5. `Release automation`
6. `Plan and deploy automation`

Suggested initial issues:

- Add repository governance files.
- Add Pester PR validation.
- Protect the `main` branch.
- Provision the FPAC Fabric test lab.
- Validate export and adoption.
- Validate update and zero drift.
- Validate replacement and deletion.
- Validate multi-capacity fan-out.
- Validate stale-plan rejection.
- Define the PowerShell module public interface.
- Build the module package.
- Create the MkDocs site.
- Publish documentation through GitHub Pages.
- Publish the PowerShell module.
- Configure GitHub OIDC for Fabric.
- Add approval-gated plan and deployment.

Each issue should define observable completion criteria rather than only an
implementation activity.

---

# Security and operational principles

Apply these principles throughout the project:

- Never commit access tokens, client secrets, tenant exports, or customer data.
- Use OIDC rather than long-lived GitHub credentials.
- Use least privilege for workspace, capacity, and tenant administration.
- Start with capacity scope and test tenant scope last.
- Keep `OwnedOnly` as the safe default.
- Require explicit authorization for adoption and activation replacement.
- Treat deployment plans as immutable review artifacts.
- Reject stale plans rather than applying potentially outdated intent.
- Pause test capacities when they are not being used.
- Keep generated output out of source control.
- Add regression coverage for every live defect.
- Do not claim support for a scenario until it has live test evidence.

---

# Final release readiness checklist

FPAC is ready for its first alpha release when:

- [ ] Repository governance and branch rules are active.
- [ ] Pester passes in pull-request CI.
- [ ] Capacity-scoped export, adoption, update, replacement, and deletion pass.
- [ ] Multi-capacity fan-out passes.
- [ ] Stale plans are rejected.
- [ ] Zero drift is demonstrated after deployment.
- [ ] The public PowerShell commands are stable.
- [ ] The staged module imports and passes tests.
- [ ] The documentation site builds strictly and is published.
- [ ] The module release workflow is protected.
- [ ] The plan/deploy workflow uses OIDC.
- [ ] Deployment requires protected-environment approval.
- [ ] The exact reviewed plan artifact is deployed.
- [ ] Post-deployment planning confirms zero drift.
- [ ] Security, contribution, support, and release policies are documented.
