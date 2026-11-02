# Deployment identities and permissions

## FPAC identity model

Use separate planning and deployment service principals with federated
credentials to maintain separation of duties. Use one planning principal per
tenant, optionally split further by environment, and a separate deployment
principal for each environment.

Fabric resource permissions are separate from Azure RBAC assignments.
Azure `Reader`, `Resource Policy Contributor`, and
`Role Based Access Control Administrator` do not grant Fabric workspace/item
permissions. FPAC does not deploy Azure role assignments, so there is no
role-deployment action.

| Identity | Boundary | Access |
|---|---|---|
| `fpac-plan-<tenant>` | One tenant, optionally split further by environment | Read all workspaces, capacities, Policy Sets, and rules needed for complete discovery; no policy writes or activation privileges |
| `fpac-deploy-<environment>` | Only that environment's governance workspaces and scopes | Same discovery visibility as planning, plus create/update/delete Policy Sets and rules; scope administration only where activation/deactivation requires it |
| Release publisher | Product repository only | PowerShell Gallery publishing key; no Fabric permissions |

Both plan and deploy discover live state. Their inventory visibility must be
consistent, including workspaces referenced by policy parameters, not just
workspaces storing Policy Sets. A reader seeing fewer resources can miss drift
or produce an incomplete picture. A successful API response is not proof of
complete visibility: verify both identities against an administrator-reviewed
inventory in a disposable scope.

## Fabric prerequisites

1. A Fabric administrator enables **Service principals can use Fabric APIs**,
   preferably restricted to a security group containing the FPAC principals.
2. Grant planning read access to required governance items/workspaces (a
   workspace Viewer role is a starting point; verify each preview endpoint).
3. Grant deployment the workspace/item permissions needed for Policy Set and
   rule creation, modification, and deletion. Workspace Contributor is a
   starting point; validate the actual endpoint permission requirements.
4. Ensure capacity discovery works for both identities. The
   [List Capacities API](https://learn.microsoft.com/rest/api/fabric/core/capacities/list-capacities)
   returns capacities accessible as an administrator or contributor. Planning
   therefore needs the contributor visibility required by that endpoint, not
   merely workspace Viewer access. This can be broader than pure read access:
   assess and approve that capacity entitlement explicitly. Do not make the
   reader a capacity administrator to work around discovery. If the required
   visibility cannot be granted acceptably, do not enable live automation for
   that boundary.
5. For capacity activation, the caller must be an administrator of that
   capacity and have read permission on the Policy Set. Tenant activation
   requires the appropriate Fabric administrator authority.

The [Fabric policy API overview](https://learn.microsoft.com/fabric/governance/fabric-policies-rest-api)
documents user, service-principal, and managed-identity support, and the
[activation reference](https://learn.microsoft.com/rest/api/fabric/policyset/activation/activate)
documents capacity administration and supported identities.
Check the identity-support and permission sections of **every endpoint used**
before granting production access. Support in a general overview does not
guarantee every tenant-scope preview operation works with an application.
If tenant activation is unavailable to the proposed identity, keep tenant
enforcement manual and explicitly approved; do not substitute a stored user
password, refresh token, or interactive user session in CI.

Delegated scopes such as `Workspace.Read.All`, `Item.ReadWrite.All`, and
`Capacity.ReadWrite.All` describe **user-token** authorization. They are not a
recipe for application permissions. App-only access requires the Fabric tenant
setting, supported endpoints, and resource authorization.
See [Fabric identity support](https://learn.microsoft.com/rest/api/fabric/articles/identity-support).

## GitHub OIDC setup

In the **consumer policy repository**, create GitHub environments:

| GitHub environment | App registration | Protection |
|---|---|---|
| `FPAC-PLAN` | Planning application | Only protected `main`; restrict workflow changes |
| `FPAC-PRODUCTION-DEPLOY` | Production deployment application | Only protected `main`; required independent reviewers; prevent self-review; disable bypass where available |

Create one Entra application/service principal for each row. For each
application, create a **federated credential**, not a client secret:

```text
Issuer:   https://token.actions.githubusercontent.com
Audience: api://AzureADTokenExchange

Planning subject:
repo:<owner>/<consumer-repository>:environment:FPAC-PLAN

Deployment subject:
repo:<owner>/<consumer-repository>:environment:FPAC-PRODUCTION-DEPLOY
```

Subjects must match case and exact environment names. These are standard
GitHub environment subjects; custom organization subject templates require
matching Entra configuration. Use the consumer repository, not the public
FPAC action repository, in the subject.

Set environment variables `AZURE_TENANT_ID` and `AZURE_CLIENT_ID` in each
environment. They are identifiers, not secrets. Each job requires
`permissions: id-token: write` and `contents: read`.
The action exchanges the GitHub assertion through `Connect-AzAccount
-ServicePrincipal -FederatedToken`, then obtains Fabric tokens through
Az.Accounts. It needs no subscription ID, Azure subscription role, client
secret, or stored user credential. It disables context persistence and clears
the process context after use.

Use managed identities instead when running your own PowerShell automation
on an authorized Azure host. The supplied GitHub actions specifically use OIDC.

## Approval and trust boundaries

- Run live planning only from trusted code. Do not use `pull_request_target`
  to check out and execute an untrusted pull request with OIDC access.
- Branch rules must protect definitions, workflows, and action version pins.
  CODEOWNERS alone does not enforce approval unless branch rules require it.
- The deploy job must use a protected GitHub environment. Composite actions
  cannot impose an environment approval on the caller.
- Pin the same exact module version for both jobs and pin action references
  to a reviewed immutable commit SHA in production.
- Review plan JSON, planning logs, deletions, ownership adoption, scope
  changes, and activation replacements before approving.
- Download the plan from the **same workflow run**, compare its SHA-256 with
  the trusted planning job's output, and use settings from the same commit.
  A hash supplied alongside an attacker-supplied plan is not authorization.
- A hash verifies artifact integrity, not current live state. Existing
  deployment safeguards still apply; rebuild and reapprove if state changes.
- Retain plan artifacts only as long as needed and restrict repository access;
  artifacts and logs can contain tenant/resource identifiers and policy values.
- After deployment, build a new plan and confirm zero drift, then verify
  actual enforcement separately. API acceptance is not enforcement evidence.
