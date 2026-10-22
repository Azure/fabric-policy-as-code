function Update-FabricPolicySet {
    param (
        [Parameter(Mandatory)]
        [object] $PlanEntry,

        [Parameter(Mandatory)]
        [object] $ResolvedItem,

        [Parameter(Mandatory)]
        [hashtable] $Headers,

        [Parameter()]
        [ValidateRange(1, 7200)]
        [int] $OperationTimeoutSeconds = 1800,

        [Parameter(Mandatory)]
        [string] $PacOwnerId,

        [Parameter()]
        [switch] $AllowActivationReplacement,

        [Parameter()]
        [System.Collections.IDictionary] $CapacityMap = @{}
    )

    $desired = $PlanEntry.desired
    $changes = @($PlanEntry.changes)
    $liveOwner = [string] (Get-FabricPropertyValue -InputObject $ResolvedItem -Name 'PacOwnerId')
    if (-not [string]::IsNullOrWhiteSpace($liveOwner) -and
        -not [string]::Equals($liveOwner, $PacOwnerId, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Policy Set '$($desired.properties.displayName)' is owned by '$liveOwner', not configured PAC owner '$PacOwnerId'. Rebuild the plan."
    }
    if ([string]::IsNullOrWhiteSpace($liveOwner) -and $changes -notcontains 'ownership') {
        throw "Policy Set '$($desired.properties.displayName)' is now unowned. Rebuild an adoption plan before updating its rules."
    }
    if ($changes -contains 'displayName' -or $changes -contains 'description') {
        $metadata = Get-FabricPropertyValue -InputObject $desired -Name 'metadata'
        $owner = [string] (Get-FabricPropertyValue -InputObject $metadata -Name 'pacOwnerId')
        $description = Format-FpacOwnershipDescription `
            -Description ([string] (Get-FabricPropertyValue -InputObject $desired.properties -Name 'description')) `
            -PacOwnerId $owner -FpacId ([string] $desired.name) -MaxLength 256
        $uri = "$script:FabricApiBaseUri/workspaces/$($ResolvedItem.WorkspaceId)/policySets/$($ResolvedItem.PolicySetId)"
        $response = Invoke-FabricApiRequest -Method PATCH -Uri $uri -Headers $Headers -Body @{
            displayName = [string] $desired.properties.displayName
            description = $description
        }
        if ($response.StatusCode -ne 200) {
            throw "Fabric Policy Set metadata update returned HTTP $($response.StatusCode)."
        }
        if ($changes -contains 'displayName') {
            Write-FpacModernStatus -Message "Renamed: $($desired.properties.workspace)/$($PlanEntry.deployed.properties.displayName) -> $($desired.properties.displayName)" -Status update -Indent 4
        }
        if ($changes -contains 'description') {
            Write-FpacModernStatus -Message "Updated description: $($desired.properties.workspace)/$($desired.properties.displayName)" -Status update -Indent 4
        }
    }

    if ($changes -contains 'policies' -or $changes -contains 'ownership') {
        Set-FabricPolicySetRules -PolicySet $desired `
            -WorkspaceId $ResolvedItem.WorkspaceId `
            -PolicySetId $ResolvedItem.PolicySetId `
            -Headers $Headers `
            -OperationTimeoutSeconds $OperationTimeoutSeconds
    }

    $desiredStatus = [string] $desired.properties.status
    $deployedStatus = [string] $PlanEntry.deployed.properties.status
    $scopeChanged = $changes -contains 'scope'
    if ($deployedStatus -eq 'Active' -and ($desiredStatus -eq 'Inactive' -or $scopeChanged)) {
        Set-FabricPolicySetStatus -WorkspaceId $ResolvedItem.WorkspaceId `
            -PolicySetId $ResolvedItem.PolicySetId `
            -Scope $PlanEntry.deployed.properties.scope `
            -DesiredStatus Inactive -CurrentStatus Active `
            -Headers $Headers -ResourceLabel "$($desired.properties.workspace)/$($desired.properties.displayName)" `
            -CapacityMap $CapacityMap
        $deployedStatus = 'Inactive'
    }
    if ($desiredStatus -eq 'Active' -and ($deployedStatus -eq 'Inactive' -or $scopeChanged)) {
        Set-FabricPolicySetStatus -WorkspaceId $ResolvedItem.WorkspaceId `
            -PolicySetId $ResolvedItem.PolicySetId `
            -Scope $desired.properties.scope `
            -DesiredStatus Active -CurrentStatus Inactive `
            -Headers $Headers `
            -AllowReplace:$AllowActivationReplacement `
            -ResourceLabel "$($desired.properties.workspace)/$($desired.properties.displayName)" -CapacityMap $CapacityMap
    }
}
