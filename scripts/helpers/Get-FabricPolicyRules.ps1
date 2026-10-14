function Get-FabricPolicyRules {
    param (
        [Parameter(Mandatory)]
        [string] $WorkspaceId,

        [Parameter(Mandatory)]
        [string] $PolicySetId,

        [Parameter(Mandatory)]
        [hashtable] $Headers
    )

    $uri = "$script:FabricApiBaseUri/workspaces/$WorkspaceId/policySets/$PolicySetId/policyRules?beta=true"
    return @(Get-FabricPagedCollection -Uri $uri -Headers $Headers)
}
