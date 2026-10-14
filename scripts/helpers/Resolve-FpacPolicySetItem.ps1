function Resolve-FpacPolicySetItem {
    param (
        [Parameter(Mandatory)]
        [System.Collections.IDictionary] $Inventory,

        [Parameter(Mandatory)]
        [object] $PolicySet,

        [Parameter()]
        [switch] $AllowMissing
    )

    $workspaceName = [string] $PolicySet.properties.workspace
    $displayName = [string] $PolicySet.properties.displayName
    if (-not $Inventory.Contains($workspaceName)) {
        throw "Workspace '$workspaceName' was not returned by Fabric during deployment."
    }
    $workspace = $Inventory[$workspaceName]
    if (-not $workspace.PolicySets.ContainsKey($displayName)) {
        if ($AllowMissing) {
            return $null
        }
        throw "Policy Set '$displayName' was not found in workspace '$workspaceName'. The deployment plan may be stale."
    }

    return [pscustomobject]@{
        WorkspaceId   = $workspace.Id
        WorkspaceName = $workspace.Name
        PolicySetId   = [string] (Get-FabricPropertyValue -InputObject $workspace.PolicySets[$displayName] -Name 'Id')
        DisplayName   = $displayName
        Description   = [string] (Get-FabricPropertyValue -InputObject $workspace.PolicySets[$displayName] -Name 'Description')
        PacOwnerId    = [string] (Get-FabricPropertyValue -InputObject $workspace.PolicySets[$displayName] -Name 'PacOwnerId')
    }
}
