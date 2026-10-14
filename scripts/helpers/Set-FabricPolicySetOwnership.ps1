function Set-FabricPolicySetOwnership {
    param (
        [Parameter(Mandatory)]
        [object] $PolicySet,

        [Parameter(Mandatory)]
        [object] $ResolvedItem,

        [Parameter(Mandatory)]
        [string] $PacOwnerId,

        [Parameter(Mandatory)]
        [hashtable] $Headers
    )

    $humanDescription = [string] (Get-FabricPropertyValue -InputObject $PolicySet.properties -Name 'description')
    $metadata = Get-FabricPropertyValue -InputObject $PolicySet -Name 'metadata'
    $fpacId = [string] (Get-FabricPropertyValue -InputObject $metadata -Name 'fpacId')
    if ([string]::IsNullOrWhiteSpace($fpacId)) {
        $fpacId = [string] $PolicySet.name
    }
    $description = Format-FpacOwnershipDescription -Description $humanDescription `
        -PacOwnerId $PacOwnerId -FpacId $fpacId -MaxLength 256
    $uri = "$script:FabricApiBaseUri/workspaces/$($ResolvedItem.WorkspaceId)/policySets/$($ResolvedItem.PolicySetId)"
    $response = Invoke-FabricApiRequest -Method PATCH -Uri $uri -Headers $Headers -Body @{
        description = $description
    }
    if ($response.StatusCode -ne 200) {
        throw "Fabric Policy Set ownership update returned HTTP $($response.StatusCode)."
    }
}
