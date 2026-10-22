# Fabric setup and manually creating a policy

This guide takes you from Fabric access to a manually created and activated Policy Set. Fabric policies and their REST APIs are preview features; labels and portal steps can change.

## 1. Get access to a Fabric tenant

1. Use an organization's Microsoft Entra tenant. If you don't have an organization account, ask your organization's IT administrator to provide one; Fabric policies aren't created from a personal Microsoft account.
2. Sign in at [app.fabric.microsoft.com](https://app.fabric.microsoft.com/). A Fabric administrator must first enable Fabric for the organization using the **Users can create Fabric items** tenant setting.
3. For a learning environment, start a [Fabric trial](https://learn.microsoft.com/fabric/fundamentals/fabric-trial) from Fabric's account manager, subject to your tenant's trial settings. For an organization environment, use an assigned capacity that supports Fabric, such as an Azure F SKU, a supported Power BI Premium P SKU, or a Fabric trial capacity. A per-user license by itself doesn't provide Fabric capacity.
4. Create a workspace or open one you can administer. Assign it to a Fabric capacity or trial capacity; for a trial, use the **Trial** workspace license mode. The policy set item is stored in this workspace.

References: [Enable Microsoft Fabric for your organization](https://learn.microsoft.com/fabric/admin/fabric-switch), [Understand Microsoft Fabric licenses and capacity](https://learn.microsoft.com/fabric/enterprise/licenses), [Buy Fabric capacity in Azure](https://learn.microsoft.com/fabric/enterprise/buy-capacity), and [Try Microsoft Fabric for free](https://learn.microsoft.com/fabric/fundamentals/fabric-trial).

If no Fabric administrator is available, a Microsoft 365 user administrator can assign the **Fabric administrator** role in the Microsoft 365 admin portal. Capacity administrators are assigned on their capacity. See [Understand Microsoft Fabric admin roles](https://learn.microsoft.com/fabric/admin/roles).

## 2. Enable Fabric Policies

### Enable for the whole tenant

To enable policy authoring across the organization, a **Fabric administrator**
or **Power Platform administrator** should use the tenant-level configuration:

1. In the Fabric portal, select the **Settings** (gear) icon.
2. Select **Admin portal** > **Tenant settings**.
3. Filter the tenant settings by the keyword **Policies**, expand the
   **Policies** section, and set the toggle to **Enabled**.
4. Under **Apply to**, choose **The entire organization**. To exclude selected
   groups, choose **Except specific security groups** and select those groups.
   Alternatively, apply the setting only to selected security groups.
5. Select **Apply** to save the change.

This is the setting location to use when you want the **Policies (preview)** feature enabled for the entire tenant. The Microsoft guide calls this the **Policies tenant setting**.

Microsoft is rolling out tenant administration inside **OneLake catalog** >
**Govern**. In tenants where it is available to the signed-in administrator,
**Configurations** > **Tenant settings** reaches the same settings. If
**Configurations** shows only **Support** entries such as **Known issues**,
**Service health**, and **Support requests**, use the **Admin portal** route
above instead.

If **Admin portal** or **Tenant settings** isn't available, ask a Microsoft 365
user administrator to assign the **Fabric administrator** or **Power Platform
administrator** role, then sign out and back in before retrying. Being a
capacity administrator or workspace administrator isn't sufficient to change
an organization-wide tenant setting.

To verify the role, sign in to the
[Microsoft Entra admin center](https://entra.microsoft.com/) with the same
account and tenant used in Fabric. Open **Entra ID** > **Users**, select your
user, and then select **Assigned roles**. Look for an active **Fabric
Administrator**, **Power Platform Administrator**, or **Global Administrator**
assignment. These are Microsoft Entra directory roles; they don't appear under
an Azure subscription's **Access control (IAM)** page.

If the organization uses Privileged Identity Management and the role is
eligible rather than active, open **Identity governance** > **Privileged
Identity Management** > **My roles** > **Microsoft Entra roles** and activate
it. After assignment or activation, sign out of Fabric and sign back in before
checking **Admin portal** > **Tenant settings** again.

### Enable or override for one capacity

To manage the delegated setting for a particular capacity instead, open **OneLake catalog** > **Capacities**, select the ellipsis (**…**) next to the capacity, then choose **Settings** > **Delegated tenant settings** > **Policies (preview)**. Use this capacity-level setting when you need to manage policy availability specifically for that capacity. It is not the tenant-wide **Apply to: The entire organization** control described above.

Capacity delegated settings can affect behavior for that capacity, so check both the tenant configuration and the capacity's delegated tenant settings when the feature appears enabled globally but is unavailable in a particular capacity.

Separately, confirm the **Users can create Fabric items** tenant setting is enabled for the intended users, and that the policy-set workspace is assigned to a Fabric capacity.

The Policies tenant setting controls access to creating policy sets; it is distinct from the administrator role needed to activate a policy at its chosen scope.

## 3. Confirm roles and scope before creating the item

- The workspace must be assigned to a Fabric capacity.
- To create a policy set item, the user needs **Contributor**, **Member**, or **Admin** access to its workspace and must be allowed by the Policies tenant setting.
- A policy set has one of two administrative scopes, selected at creation: **Fabric tenant** or **a capacity**. This scope can't be changed later.
- Tenant-scope activation requires a **Fabric administrator**. Capacity-scope activation requires an administrator of the selected capacity.
- Add Entra security groups if policy rules will target users or groups.
- Enable Microsoft Purview Information Protection if rules will use sensitivity-label conditions.

If you only have a per-user license and no capacity-backed or trial workspace, ask an administrator to provide a workspace on a supported capacity.

## 4. Create a Policy Set item

1. In Fabric, open the capacity-backed workspace.
2. Select **New item** > **Policy set**.
3. Enter a name and choose the administrative scope:
   - **Fabric tenant** for a Fabric administrator to activate the policy tenant-wide.
   - **A capacity** for a capacity administrator to activate it for a particular capacity.
4. Create the item. Fabric stores the policy set as a workspace item. The workspace where it is stored does not replace the admin scope that you chose.

## 5. Add a policy rule

1. Open the Policy Set item. The supported policy types are already listed in the set; there isn't a separate **Add policy** action.
2. Find the policy to configure (for example, **Users can create items**) and choose **Allowed**, **Blocked**, or **Advanced**. **Advanced** enables rule authoring for that policy.
3. Under **Advanced**, select **Add rule** or **Create rule**. Give the rule a display name and, optionally, a description.
4. Add the conditions supported by that policy type. Depending on the policy, conditions can target security groups, workspaces, item types, sensitivity labels, or recipient email domains. Choose **Is any of** or **Is none of** and select or enter values.
5. Review the rule and select **Apply**. This adds a rule to the selected policy, not a new policy type. Repeat for another allow scenario.

Conditions in one rule use **AND** logic, and separate rules for that policy use **OR** logic. For an **Allow** policy in Advanced mode, rules act as an allow list: matching operations are allowed, and nonmatching operations can be denied. Read the current portal explanation carefully before saving.

## 6. Review and activate

1. Review the policy set and its rules in the workspace.
2. Select **Active** from the policy item.
3. For a capacity-scoped policy set, select the target capacity when prompted and review the activation confirmation. For tenant scope, activation is performed by a Fabric administrator.
4. Validate the policy using an in-scope and out-of-scope test identity/action, and review the Policies center in the OneLake catalog for active policy visibility.

Activation is an enforcement action. A new Policy Set starts inactive, and any number of inactive Policy Sets can be retained as drafts or rollback copies. Only one Policy Set can be active for a tenant or capacity scope at a time. Activating another set replaces the currently active set; it does not merge their rules, and the change can take up to 15 minutes to take effect.

Git integration can version policy-set definitions, but Git alone doesn't activate a policy. To deactivate or replace an active policy set, return to the item and use its policy controls; an administrator of the policy's scope is required.

## Troubleshooting and caveats

- If **Policy set** or the Policies controls are missing, check the Policies tenant setting, security-group targeting, workspace capacity assignment, and the user's workspace role.
- If activation is unavailable, check the selected admin scope and whether the operator is a Fabric administrator or administrator of the target capacity.
- Current preview limitations include scope/condition and policy-type constraints. Review the latest overview and manage-policy documentation before broad enforcement.
- FPAC's exporter enumerates workspaces visible to its Entra identity and reads Policy Set scope information and rules using the Policy Set-specific APIs. Workspace, scope, activation status, and instance display name are recorded in the deployment declaration, while reusable rule composition remains in the Policy Set definition.
- The delegated scopes are `Workspace.Read.All` or `Workspace.ReadWrite.All` for workspace discovery and `Item.Read.All` or `Item.ReadWrite.All` for Policy Set/rule reads.

## FPAC target configuration

FPAC uses [global-settings.jsonc](../Definitions/global-settings.jsonc) for named environments, following EPAC's environment-selection pattern:

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

The exporter prompts you to select a configured environment; `-EnvironmentName` selects one noninteractively. Every environment has one `tenantId`. A Tenant environment contains one tenant scope and enumerates all Policy Sets visible to that identity, including capacity-scoped sets. A Capacity environment can contain multiple capacity scopes and exports Policy Sets assigned to any configured capacity ID. Scope entries in an environment must all be tenant entries or all be capacity entries; the two types cannot be mixed. The active Az.Accounts tenant must match the selected environment's `tenantId`.

Exports place one reusable FPAC policy definition per Fabric rule under `policyDefinitions/`, a value-free reusable composition under `policySets/`, and a compact deployment declaration under `assignments/`. Policy definitions declare parameters without defaults, and every concrete parameter value is stored in the assignment. Every exported deployment target records the source workspace and activation scope together, while its child records the instance display name, activation status, and parameter values.

Promote artifacts you intend to manage from the environment export into the flat EPAC-style folders `Definitions/policyDefinitions`, `Definitions/policySetDefinitions`, and `Definitions/policyAssignments`. The `policyAssignments` name is retained for EPAC familiarity, but these files are fan-out deployment declarations rather than Fabric assignment resources.

A single deployment declaration places its display name, parameters, activation state, and environment-keyed `targets` directly under `properties`; no `children` array is needed. Use `children` only when one file defines several deployment variations with different shared values. Every target pairs a storage workspace with an activation `scope` and materializes one real Fabric Policy Set. The workspace only needs to be capacity-backed; it does not need to use the capacity governed by the Policy Set. This permits a central governance workspace to store Policy Sets for several capacities. Capacity scopes use the capacity name without an ID or `type`; tenant-wide scopes use `type: "Tenant"`.

Capacity entries are authored with a `name` only; the absence of `type` identifies them as capacity scopes. Export and planning retrieve accessible Fabric capacities and resolve each display name to its ID. In a capacity environment, the resolved assignment capacity must also appear in that environment's configured scope array.

Plan generation validates each target workspace against the workspaces visible to the signed-in identity. Names are matched case-insensitively, but they must resolve uniquely and the workspace must be assigned to a Fabric capacity. A misspelled, inaccessible, unlicensed, or duplicated workspace name stops planning before a plan file is written, and any previous plan for that environment is removed.

Use `scripts/Deploy/Build-DeploymentPlans.ps1` to compare `Definitions` with live Fabric state. The read-only operation resolves templates and parameter overrides into concrete Policy Sets, then produces `new`, `update`, `replace`, `adopt`, and `delete` actions only for those real Fabric resources. It rejects multiple desired active Policy Sets for the same scope, including conflicts declared in different FPAC environments.

FPAC stores ownership in Policy Set and Policy Rule descriptions using a marker such as `[[FPAC:v1;owner=contoso-fpac;id=stable-id]]`; the human description remains intact. `OwnedOnly`, the default desired-state strategy, updates and deletes only resources owned by the configured `pacOwnerId` and preserves unowned objects. `Full` can delete unowned objects absent from desired state inside the selected management boundary. A matching unowned object is an adoption in either mode and deployment requires `-AdoptUnowned`. Objects owned by another PAC owner are not silently changed.

Use `scripts/Deploy/Deploy-Policy.ps1 -EnvironmentName <name> -WhatIf` to preview the reviewed plan. A real deployment validates that activation state has not changed since planning. If the plan intentionally replaces the active set on a scope, pass `-AllowActivationReplacement`; FPAC will not use Fabric's replacement behavior as an invisible side effect. Capacity-to-capacity reassignment is handled as a deactivate-and-activate update, while a tenant-to-capacity scope-type change requires replacement.

## References

- [What are Microsoft Fabric policies?](https://learn.microsoft.com/fabric/governance/fabric-policies-overview)
- [Get started with Microsoft Fabric policies](https://learn.microsoft.com/fabric/governance/fabric-policies-get-started)
- [Manage policies in the OneLake catalog Policies center](https://learn.microsoft.com/fabric/governance/fabric-policies-manage-onelake-catalog)
- [Fabric policies REST APIs](https://learn.microsoft.com/fabric/governance/fabric-policies-rest-api)
- [Fabric REST API documentation structure](https://learn.microsoft.com/rest/api/fabric/articles/api-structure)
- [PolicySet definition](https://learn.microsoft.com/rest/api/fabric/articles/item-management/definitions/policyset-definition)
- [Fabric REST API: List Workspaces](https://learn.microsoft.com/rest/api/fabric/core/workspaces/list-workspaces)
- [Fabric REST API: List Items](https://learn.microsoft.com/rest/api/fabric/core/items/list-items)
- [Fabric REST API: Get Policy Set](https://learn.microsoft.com/rest/api/fabric/policyset/items/get-policy-set)
- [Fabric REST API: List Policy Rules (beta)](https://learn.microsoft.com/rest/api/fabric/policyset/policy-rules/list-policy-rules(beta))
- [Understand Microsoft Fabric admin roles](https://learn.microsoft.com/fabric/admin/roles)
- [Fabric September 2026 feature summary](https://community.fabric.microsoft.com/blog/fbc_fabricupdatesblogs/fabric-september-2026-feature-summary/5325825)
- [SBL Fabric Policies internal wiki](https://supportability.visualstudio.com/Fabric/_wiki/wikis/Fabric/2988420/SBL-Fabric-Policies) (requires access to the internal Azure DevOps organization)
- [FPAC global settings](../Definitions/global-settings.jsonc)
