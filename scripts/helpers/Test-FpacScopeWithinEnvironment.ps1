function Test-FpacScopeWithinEnvironment {
    param (
        [Parameter(Mandatory)]
        [object] $Scope,

        [Parameter(Mandatory)]
        [pscustomobject] $Target
    )

    $scopeType = [string] $Scope.type
    if ($Target.ScopeType -eq 'Tenant') {
        $includeCapacities = Get-FabricPropertyValue -InputObject $Target.Scopes[0] -Name 'IncludeCapacities'
        if ($includeCapacities -isnot [bool]) {
            throw "Tenant environment '$($Target.Name)' must explicitly set includeCapacities to true or false."
        }
        return $scopeType -eq 'Tenant' -or ($includeCapacities -and $scopeType -eq 'Capacity')
    }

    return $scopeType -eq 'Capacity' -and [string] $Scope.id -in @($Target.CapacityIds)
}
