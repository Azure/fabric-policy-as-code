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

        [Parameter()]
        [string] $PacOwnerId,

        [Parameter()]
        [ValidateSet('OwnedOnly', 'Full')]
        [string] $DesiredStateStrategy = 'OwnedOnly',

        [Parameter()]
        [switch] $AdoptUnowned,

        [Parameter()]
        [switch] $AllowActivationReplacement
    )

    $desired = $PlanEntry.desired
    $changes = @($PlanEntry.changes)
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
    }

    if ($changes -contains 'policies') {
        Set-FabricPolicySetRules -PolicySet $desired `
            -WorkspaceId $ResolvedItem.WorkspaceId `
            -PolicySetId $ResolvedItem.PolicySetId `
            -Headers $Headers `
            -PacOwnerId $PacOwnerId `
            -DesiredStateStrategy $DesiredStateStrategy `
            -AdoptUnowned:$AdoptUnowned `
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
            -Headers $Headers
        $deployedStatus = 'Inactive'
    }
    if ($desiredStatus -eq 'Active' -and ($deployedStatus -eq 'Inactive' -or $scopeChanged)) {
        Set-FabricPolicySetStatus -WorkspaceId $ResolvedItem.WorkspaceId `
            -PolicySetId $ResolvedItem.PolicySetId `
            -Scope $desired.properties.scope `
            -DesiredStatus Active -CurrentStatus Inactive `
            -Headers $Headers `
            -AllowReplace:$AllowActivationReplacement
    }
}
