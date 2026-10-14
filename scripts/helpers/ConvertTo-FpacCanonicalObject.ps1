function ConvertTo-FpacCanonicalObject {
    param (
        [Parameter()]
        [AllowNull()]
        [object] $InputObject
    )

    if ($null -eq $InputObject) {
        return $null
    }
    if ($InputObject -is [System.Collections.IDictionary]) {
        $normalized = [ordered]@{}
        foreach ($key in @($InputObject.Keys) | Sort-Object) {
            $normalized[[string] $key] = ConvertTo-FpacCanonicalObject -InputObject $InputObject[$key]
        }
        return $normalized
    }
    if ($InputObject -is [pscustomobject]) {
        $normalized = [ordered]@{}
        foreach ($property in @($InputObject.PSObject.Properties) | Sort-Object Name) {
            $normalized[$property.Name] = ConvertTo-FpacCanonicalObject -InputObject $property.Value
        }
        return $normalized
    }
    if ($InputObject -is [System.Collections.IEnumerable] -and $InputObject -isnot [string]) {
        $normalized = [System.Collections.Generic.List[object]]::new()
        foreach ($item in $InputObject) {
            $normalized.Add((ConvertTo-FpacCanonicalObject -InputObject $item))
        }
        return ,$normalized.ToArray()
    }
    return $InputObject
}
