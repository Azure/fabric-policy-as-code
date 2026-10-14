function Set-FabricPolicySetStatus {
    param (
        [Parameter(Mandatory)]
        [string] $WorkspaceId,

        [Parameter(Mandatory)]
        [string] $PolicySetId,

        [Parameter(Mandatory)]
        [object] $Scope,

        [Parameter(Mandatory)]
        [ValidateSet('Active', 'Inactive')]
        [string] $DesiredStatus,

        [Parameter()]
        [ValidateSet('Active', 'Inactive', '')]
        [string] $CurrentStatus = '',

        [Parameter(Mandatory)]
        [hashtable] $Headers,

        [Parameter()]
        [switch] $AllowReplace
    )

    if ($DesiredStatus -eq $CurrentStatus) {
        return
    }

    $scopeType = [string] $Scope.type
    if ($scopeType -eq 'Tenant') {
        $action = if ($DesiredStatus -eq 'Active') { "activate?allowReplace=$($AllowReplace.ToString().ToLowerInvariant())" } else { 'deactivate' }
        $uri = "$script:FabricApiBaseUri/admin/workspaces/$WorkspaceId/policySets/$PolicySetId/$action"
        $response = Invoke-FabricApiRequest -Method POST -Uri $uri -Headers $Headers
    }
    elseif ($scopeType -eq 'Capacity') {
        $action = if ($DesiredStatus -eq 'Active') { "activate?allowReplace=$($AllowReplace.ToString().ToLowerInvariant())" } else { 'deactivate' }
        $uri = "$script:FabricApiBaseUri/workspaces/$WorkspaceId/policySets/$PolicySetId/$action"
        $body = [ordered]@{ scopeType = 'Capacity' }
        if ($DesiredStatus -eq 'Active') {
            $body['capacityId'] = [string] $Scope.id
        }
        $response = Invoke-FabricApiRequest -Method POST -Uri $uri -Headers $Headers -Body $body
    }
    else {
        throw "Unsupported Policy Set scope type '$scopeType'."
    }

    if ($response.StatusCode -ne 200) {
        throw "Fabric Policy Set $($DesiredStatus.ToLowerInvariant()) operation returned HTTP $($response.StatusCode)."
    }
}
