function Resolve-FpacEnvironmentCapacityScopes {
    param (
        [Parameter(Mandatory)]
        [pscustomobject] $Target,

        [Parameter(Mandatory)]
        [System.Collections.IDictionary] $CapacityMap
    )

    if ($Target.ScopeType -eq 'Tenant') {
        return $Target
    }

    $resolvedScopes = [System.Collections.Generic.List[object]]::new()
    foreach ($scope in @($Target.Scopes)) {
        $capacityName = [string] $scope.Name
        if (-not $CapacityMap.Contains($capacityName)) {
            throw "Capacity '$capacityName' configured for environment '$($Target.Name)' was not returned by Fabric."
        }
        $resolvedScopes.Add([pscustomobject]@{
            Type = 'Capacity'
            Name = $capacityName
            CapacityId = [string] $CapacityMap[$capacityName]
        })
    }

    return [pscustomobject]@{
        Name = $Target.Name
        TenantId = $Target.TenantId
        ScopeType = 'Capacity'
        Scopes = $resolvedScopes.ToArray()
        CapacityIds = @($resolvedScopes.ToArray() | ForEach-Object CapacityId)
    }
}
