function Resolve-FpacParameterValue {
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

    $text = [string] $Value
    if ($referenceMap.Contains($text)) {
        return [string] $referenceMap[$text]
    }
    if (@($referenceMap.Values | Where-Object {
        [string]::Equals([string] $_, $text, [System.StringComparison]::OrdinalIgnoreCase)
    }).Count -gt 0) {
        return $Value
    }

    throw "Parameter value '$text' for '$TargetProperty' was not returned by Fabric as an accessible resource name or id."
}
