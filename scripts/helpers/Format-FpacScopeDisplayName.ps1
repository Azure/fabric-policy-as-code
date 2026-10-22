function Format-FpacScopeDisplayName {
    param (
        [Parameter(Mandatory)]
        [string] $ScopeKey,

        [Parameter()]
        [System.Collections.IDictionary] $CapacityMap = @{}
    )

    if ($ScopeKey -eq 'Tenant') {
        return 'Tenant'
    }
    if ($ScopeKey -eq 'Capacity:Unbound') {
        return 'Capacity (unassigned)'
    }
    if ($ScopeKey -like 'Capacity:*') {
        $capacityId = $ScopeKey.Substring('Capacity:'.Length)
        $names = @($CapacityMap.Keys | Where-Object {
            [string]::Equals([string] $CapacityMap[$_], $capacityId, [System.StringComparison]::OrdinalIgnoreCase)
        } | Sort-Object)
        if ($names.Count -gt 0) {
            return "Capacity: $($names -join ', ')"
        }
        return "Capacity: $capacityId (name unavailable)"
    }
    throw "Unsupported activation scope '$ScopeKey'."
}
