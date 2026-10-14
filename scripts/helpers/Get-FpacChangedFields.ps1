function Get-FpacChangedFields {
    param (
        [Parameter(Mandatory)]
        [object] $Desired,

        [Parameter(Mandatory)]
        [object] $Deployed
    )

    $fieldNames = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
    foreach ($property in @($Desired.PSObject.Properties)) {
        [void] $fieldNames.Add($property.Name)
    }
    foreach ($property in @($Deployed.PSObject.Properties)) {
        [void] $fieldNames.Add($property.Name)
    }

    $changed = [System.Collections.Generic.List[string]]::new()
    foreach ($fieldName in @($fieldNames) | Sort-Object) {
        $desiredValue = Get-FabricPropertyValue -InputObject $Desired -Name $fieldName
        $deployedValue = Get-FabricPropertyValue -InputObject $Deployed -Name $fieldName
        if ((ConvertTo-FpacCanonicalJson -InputObject $desiredValue) -cne
            (ConvertTo-FpacCanonicalJson -InputObject $deployedValue)) {
            $changed.Add($fieldName)
        }
    }
    return $changed.ToArray()
}
