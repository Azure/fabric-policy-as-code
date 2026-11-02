function ConvertTo-FpacPlanDisplayValue {
    param (
        [Parameter()]
        [AllowNull()]
        [object] $Value,

        [Parameter()]
        [string] $TargetProperty,

        [Parameter()]
        [System.Collections.IDictionary] $WorkspaceMap = @{}
    )

    if ($null -eq $Value) { return $null }
    if ($Value -is [System.Collections.IDictionary] -or $Value -is [pscustomobject]) {
        $properties = if ($Value -is [System.Collections.IDictionary]) {
            @($Value.Keys | ForEach-Object { [pscustomobject]@{ Name = [string] $_; Value = $Value[$_] } })
        }
        else { @($Value.PSObject.Properties) }
        $metadata = Get-FabricPropertyValue -InputObject $Value -Name 'metadata'
        $result = [ordered]@{}
        foreach ($property in $properties) {
            $childTarget = switch ($property.Name) {
                'defaultValue' { [string] (Get-FabricPropertyValue -InputObject $metadata -Name 'targetProperty') }
                'predicate' { [string] (Get-FabricPropertyValue -InputObject $Value -Name 'targetProperty') }
                'values' { $TargetProperty }
                'workspace' { 'workspace.id' }
                default { '' }
            }
            $result[$property.Name] = ConvertTo-FpacPlanDisplayValue -Value $property.Value `
                -TargetProperty $childTarget -WorkspaceMap $WorkspaceMap
        }
        return [pscustomobject] $result
    }
    if ($Value -is [System.Collections.IEnumerable] -and $Value -isnot [string]) {
        $items = @(
            foreach ($item in $Value) {
                ConvertTo-FpacPlanDisplayValue -Value $item -TargetProperty $TargetProperty -WorkspaceMap $WorkspaceMap
            }
        )
        return ,$items
    }
    if ($TargetProperty -eq 'workspace.id') {
        return ConvertTo-FpacPortableParameterValue -Value $Value -TargetProperty 'workspace.id' -WorkspaceMap $WorkspaceMap
    }
    return $Value
}
