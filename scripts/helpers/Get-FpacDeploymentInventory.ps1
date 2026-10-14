function Get-FpacDeploymentInventory {
    param (
        [Parameter(Mandatory)]
        [hashtable] $Headers
    )

    $inventory = [System.Collections.Hashtable]::new([System.StringComparer]::OrdinalIgnoreCase)
    $workspaces = @(Get-FabricPagedCollection -Uri "$script:FabricApiBaseUri/workspaces" -Headers $Headers)
    foreach ($workspace in $workspaces) {
        $workspaceName = [string] $workspace.displayName
        if ($inventory.ContainsKey($workspaceName)) {
            throw "Fabric returned more than one accessible workspace named '$workspaceName'."
        }

        $policySets = [System.Collections.Hashtable]::new([System.StringComparer]::OrdinalIgnoreCase)
        $items = @(Get-FabricPagedCollection -Uri "$script:FabricApiBaseUri/workspaces/$($workspace.id)/items" -Headers $Headers)
        foreach ($item in @($items | Where-Object { $_.type -eq 'PolicySet' })) {
            $displayName = [string] $item.displayName
            if ($policySets.ContainsKey($displayName)) {
                throw "Workspace '$workspaceName' contains more than one Policy Set named '$displayName'."
            }
            $details = Get-FabricPolicySet -WorkspaceId ([string] $workspace.id) `
                -PolicySetId ([string] $item.id) -Headers $Headers
            $ownership = Get-FpacOwnershipMetadata -Description ([string] $item.description)
            $policySets[$displayName] = [pscustomobject]@{
                Id          = [string] $item.id
                DisplayName = $displayName
                Description = [string] $item.description
                PacOwnerId  = if ($null -eq $ownership) { '' } else { $ownership.PacOwnerId }
                FpacId      = if ($null -eq $ownership) { '' } else { $ownership.FpacId }
                Status      = [string] (Get-FabricPropertyValue -InputObject $details.properties -Name 'status')
                Scope       = Get-FabricPropertyValue -InputObject $details.properties -Name 'scope'
            }
        }
        $inventory[$workspaceName] = [pscustomobject]@{
            Id         = [string] $workspace.id
            Name       = $workspaceName
            CapacityId = [string] (Get-FabricPropertyValue -InputObject $workspace -Name 'capacityId')
            PolicySets = $policySets
        }
    }
    return $inventory
}
