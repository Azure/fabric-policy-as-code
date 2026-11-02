# GitHub Actions

The repository supplies two composite actions:

| Action | Purpose |
|---|---|
| `Azure/fabric-policy-as-code/actions/plan` | OIDC login and nonmutating plan generation |
| `Azure/fabric-policy-as-code/actions/deploy` | OIDC login and deployment of an approved plan |

Use PowerShell 7.4+ runners with access to GitHub OIDC, Entra ID, Fabric,
PowerShell Gallery, and its dependencies. GitHub-hosted Ubuntu and Windows
runners include PowerShell. Self-hosted runners must install it beforehand.
The actions install the exact `module-version` from Gallery if missing.
The first package release must exist before consumers can run these actions.

## Consumer workflow

Copy the [plan/deploy workflow](../examples/workflows/fpac-plan-deploy.yml)
into `.github/workflows` in your private or customer-owned policy repository.
Commit your reviewed `Definitions` there; the public product repository
intentionally ignores operator definitions.

Before enabling it:

1. Configure [identities and permissions](deployment-identities.md).
2. Create and protect `FPAC-PLAN` and `FPAC-PRODUCTION-DEPLOY`.
3. Set `AZURE_TENANT_ID` and the appropriate `AZURE_CLIENT_ID` as
   environment-scoped variables.
4. Set `FPAC_ENVIRONMENT` to the environment name in global settings.
5. Select the same published module version for both jobs.
6. Replace example action tags with reviewed commit SHAs for production.
7. Complete the isolated manual deployment/read-back/zero-drift cycle with
   these identities before running against production.

The example is intentionally manual-dispatch and restricted to `main`.
It serializes planning and deployment for that boundary, never cancels a
running deployment, and pauses for deployment-environment approval.
Use a unique concurrency group for each nonoverlapping deployment boundary.
GitHub approval features depend on repository visibility and plan; do not
enable unattended production deployment without an enforceable equivalent.

## Planning contract

Required inputs: `module-version` (exact `X.Y.Z`), `tenant-id`, `client-id`,
and `environment-name`.

Optional inputs:

| Input | Default |
|---|---|
| `definitions-path` | `Definitions` |
| `global-settings-path` | `Definitions/global-settings.jsonc` |
| `output-path` | `Output` |
| `detailed-output` | `true` |

Outputs:

- `has-changes`: `true` or `false`.
- `plan-file`: absolute path to the saved plan, empty when there are no changes.
- `plan-sha256`: SHA-256 of that file, empty when there are no changes.

The action also writes a job summary. The caller uploads the plan only when
`has-changes` is `true`. A no-change plan skips deployment, not a failed
planning operation.

## Deployment contract

Required inputs: the same `module-version`, `tenant-id`, `environment-name`,
the deployment `client-id`, plus `plan-file` and the trusted planning job's
`plan-sha256`.

Optional inputs:

| Input | Default |
|---|---|
| `global-settings-path` | `Definitions/global-settings.jsonc` |
| `allow-activation-replacement` | `false` |
| `adopt-unowned` | `false` |
| `what-if` | `false` |

Boolean inputs accept `true`/`false`. Hash mismatch, missing plan/settings,
missing OIDC permissions, authentication failure, and deployment errors fail
the job. Deployment never rebuilds the plan. Noninteractive confirmation does
not bypass ownership, adoption, activation, schema, or stale-state checks.
`what-if: 'true'` performs a preview but still needs authorized read access.

The actions do not create app registrations, grant Fabric permissions, impose
reviewers, upload artifacts, or run a post-deployment zero-drift check. Those
are consumer workflow/operator responsibilities. See the example for artifact
handoff and [identity guidance](deployment-identities.md) for trust boundaries.
