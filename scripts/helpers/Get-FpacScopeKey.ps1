function Get-FpacScopeKey {
    param (
        [Parameter(Mandatory)]
        [object] $Scope
    )

    $scopeType = [string] (Get-FabricPropertyValue -InputObject $Scope -Name 'type')
    if ($scopeType -eq 'Tenant') {
        return 'Tenant'
    }
    if ($scopeType -ne 'Capacity') {
        throw "Unsupported Policy Set scope type '$scopeType'."
    }
    $capacityId = [string] (Get-FabricPropertyValue -InputObject $Scope -Name 'id')
    if ([string]::IsNullOrWhiteSpace($capacityId)) {
        return 'Capacity:Unbound'
    }
    return "Capacity:$($capacityId.ToLowerInvariant())"
}
