# Configuration and desired state

Keep tenant-specific desired state in a separate, access-controlled policy
repository. Do not commit credentials, tokens, or generated live exports.

The consumer repository supplies:

```text
Definitions/
  global-settings.jsonc
  policyDefinitions/
  policySetDefinitions/
  policyAssignments/
```

Start with an isolated capacity environment:

```json
{
  "$schema": "https://raw.githubusercontent.com/Azure/fabric-policy-as-code/main/schemas/global-settings.schema.json",
  "pacOwnerId": "contoso-fpac-development",
  "desiredStateStrategy": "OwnedOnly",
  "environments": [
    {
      "name": "Development",
      "tenantId": "<tenant-guid>",
      "scope": [{ "name": "<capacity-name>" }]
    }
  ]
}
```

Replace placeholders before running. For release-pinned schemas, replace
`main` in the URL with the package tag, for example `v0.1.0`.
Authoring supports JSONC comments and trailing commas; generated plans and
native Fabric payloads remain JSON.

Use export as a starting point, then review and promote the exported
definitions and assignments. Removing an owned assignment from desired state
can plan deletion. `Full` is broader than `OwnedOnly`; do not use it against a
shared tenant or capacity without understanding the reconciliation boundary.
Tenant scope must explicitly set `includeCapacities` to `true` or `false`.

See the [complete configuration reference](../README.md) for parameters,
composition, fan-out, ownership, and scope semantics, and the
[manual test matrix](manual-test-matrix.md) for complete isolated examples.
The canonical [settings schema](../schemas/global-settings.schema.json) is
packaged with the module.
