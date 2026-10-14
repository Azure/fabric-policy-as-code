function ConvertTo-FpacPortableParameterValue {
    param (
        [Parameter()]
        [object] $Value,

        [Parameter()]
        [string] $TargetProperty,

        [Parameter()]
        [System.Collections.IDictionary] $WorkspaceMap = @{},

        [Parameter()]
        [System.Collections.IDictionary] $CapacityMap = @{}
    )

    $referenceMap = switch ($TargetProperty) {
        'workspace.id' { $WorkspaceMap; break }
        'capacity.id' { $CapacityMap; break }
        default { $null }
    }
    if ($null -eq $referenceMap -or $null -eq $Value) {
        return $Value
    }

    $matchingNames = @($referenceMap.Keys | Where-Object {
        [string]::Equals(
            [string] $referenceMap[$_],
            [string] $Value,
            [System.StringComparison]::OrdinalIgnoreCase
        )
    })
    if ($matchingNames.Count -eq 1) {
        return [string] $matchingNames[0]
    }
    if ($matchingNames.Count -gt 1) {
        throw "More than one Fabric $TargetProperty resource resolves to id '$Value'."
    }
    return $Value
}
