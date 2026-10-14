function New-FabricPolicySet {
    param (
        [Parameter(Mandatory)]
        [object] $PolicySet,

        [Parameter(Mandatory)]
        [string] $WorkspaceId,

        [Parameter(Mandatory)]
        [hashtable] $Headers,

        [Parameter()]
        [ValidateRange(1, 7200)]
        [int] $OperationTimeoutSeconds = 1800,

        [Parameter()]
        [switch] $AllowActivationReplacement,

        [Parameter()]
        [switch] $DeferActivation
    )

    $metadata = Get-FabricPropertyValue -InputObject $PolicySet -Name 'metadata'
    $pacOwnerId = [string] (Get-FabricPropertyValue -InputObject $metadata -Name 'pacOwnerId')
    $fpacId = [string] (Get-FabricPropertyValue -InputObject $metadata -Name 'fpacId')
    if ([string]::IsNullOrWhiteSpace($fpacId)) {
        $fpacId = [string] $PolicySet.name
    }
    $humanDescription = [string] (Get-FabricPropertyValue -InputObject $PolicySet.properties -Name 'description')
    $body = [ordered]@{
        displayName = [string] $PolicySet.properties.displayName
        definition  = New-FabricPolicySetDefinition -PolicySet $PolicySet
    }
    if (-not [string]::IsNullOrWhiteSpace($pacOwnerId)) {
        $body['description'] = Format-FpacOwnershipDescription -Description $humanDescription `
            -PacOwnerId $pacOwnerId -FpacId $fpacId -MaxLength 256
    }
    $uri = "$script:FabricApiBaseUri/workspaces/$WorkspaceId/policySets"
    $response = Invoke-FabricApiRequest -Method POST -Uri $uri -Headers $Headers -Body $body
    if ($response.StatusCode -notin @(201, 202)) {
        throw "Fabric Policy Set creation returned HTTP $($response.StatusCode)."
    }
    $result = Wait-FabricLongRunningOperation -Response $response -Headers $Headers -TimeoutSeconds $OperationTimeoutSeconds

    $policySetId = [string] (Get-FabricPropertyValue -InputObject $result -Name 'id')
    if ([string]::IsNullOrWhiteSpace($policySetId)) {
        $items = @(Get-FabricPagedCollection -Uri "$script:FabricApiBaseUri/workspaces/$WorkspaceId/items" -Headers $Headers |
            Where-Object {
                $_.type -eq 'PolicySet' -and
                [string]::Equals(
                    [string] $_.displayName,
                    [string] $PolicySet.properties.displayName,
                    [System.StringComparison]::OrdinalIgnoreCase
                )
            })
        if ($items.Count -ne 1) {
            throw "Unable to resolve the newly created Policy Set '$($PolicySet.properties.displayName)' in workspace '$WorkspaceId'."
        }
        $policySetId = [string] $items[0].id
    }

    if (-not $DeferActivation) {
        Set-FabricPolicySetStatus -WorkspaceId $WorkspaceId -PolicySetId $policySetId `
            -Scope $PolicySet.properties.scope -DesiredStatus $PolicySet.properties.status `
            -CurrentStatus 'Inactive' -Headers $Headers `
            -AllowReplace:$AllowActivationReplacement
    }
    return $policySetId
}
