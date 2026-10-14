function Get-FpacObjectDifferences {
    param (
        [Parameter()]
        [AllowNull()]
        [object] $Desired,

        [Parameter()]
        [AllowNull()]
        [object] $Deployed,

        [Parameter()]
        [string] $Path = ''
    )

    if ((ConvertTo-FpacCanonicalJson -InputObject $Desired) -ceq
        (ConvertTo-FpacCanonicalJson -InputObject $Deployed)) {
        return
    }

    if ($null -eq $Deployed) {
        [pscustomobject]@{ path = $Path; change = 'Add'; oldValue = $null; newValue = $Desired }
        return
    }
    if ($null -eq $Desired) {
        [pscustomobject]@{ path = $Path; change = 'Remove'; oldValue = $Deployed; newValue = $null }
        return
    }

    $desiredIsObject = $Desired -is [System.Collections.IDictionary] -or $Desired -is [pscustomobject]
    $deployedIsObject = $Deployed -is [System.Collections.IDictionary] -or $Deployed -is [pscustomobject]
    if ($desiredIsObject -and $deployedIsObject) {
        $names = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
        $desiredProperties = if ($Desired -is [System.Collections.IDictionary]) {
            @($Desired.Keys | ForEach-Object { [pscustomobject]@{ Name = [string] $_; Value = $Desired[$_] } })
        }
        else {
            @($Desired.PSObject.Properties)
        }
        $deployedProperties = if ($Deployed -is [System.Collections.IDictionary]) {
            @($Deployed.Keys | ForEach-Object { [pscustomobject]@{ Name = [string] $_; Value = $Deployed[$_] } })
        }
        else {
            @($Deployed.PSObject.Properties)
        }
        foreach ($property in $desiredProperties) {
            [void] $names.Add($property.Name)
        }
        foreach ($property in $deployedProperties) {
            [void] $names.Add($property.Name)
        }
        foreach ($name in @($names) | Sort-Object) {
            $desiredProperty = @($desiredProperties | Where-Object Name -CEQ $name)
            $deployedProperty = @($deployedProperties | Where-Object Name -CEQ $name)
            $childPath = if ([string]::IsNullOrWhiteSpace($Path)) { $name } else { "$Path.$name" }
            $desiredValue = $null
            if ($desiredProperty.Count -gt 0) {
                $desiredValue = $desiredProperty[0].Value
            }
            $deployedValue = $null
            if ($deployedProperty.Count -gt 0) {
                $deployedValue = $deployedProperty[0].Value
            }
            Get-FpacObjectDifferences `
                -Desired $desiredValue `
                -Deployed $deployedValue `
                -Path $childPath
        }
        return
    }

    $desiredIsArray = $Desired -is [System.Collections.IEnumerable] -and $Desired -isnot [string]
    $deployedIsArray = $Deployed -is [System.Collections.IEnumerable] -and $Deployed -isnot [string]
    if ($desiredIsArray -and $deployedIsArray) {
        $desiredArray = @($Desired)
        $deployedArray = @($Deployed)
        $desiredNamed = $desiredArray.Count -gt 0 -and
            @($desiredArray | Where-Object { $null -eq $_.PSObject.Properties['name'] }).Count -eq 0
        $deployedNamed = $deployedArray.Count -gt 0 -and
            @($deployedArray | Where-Object { $null -eq $_.PSObject.Properties['name'] }).Count -eq 0
        if ($desiredNamed -and $deployedNamed) {
            $names = @(
                @($desiredArray | ForEach-Object { [string] $_.name })
                @($deployedArray | ForEach-Object { [string] $_.name })
            ) | Sort-Object -Unique
            foreach ($name in $names) {
                $desiredItem = @($desiredArray | Where-Object { [string]::Equals([string] $_.name, $name, [System.StringComparison]::Ordinal) })
                $deployedItem = @($deployedArray | Where-Object { [string]::Equals([string] $_.name, $name, [System.StringComparison]::Ordinal) })
                $desiredValue = $null
                if ($desiredItem.Count -gt 0) {
                    $desiredValue = $desiredItem[0]
                }
                $deployedValue = $null
                if ($deployedItem.Count -gt 0) {
                    $deployedValue = $deployedItem[0]
                }
                Get-FpacObjectDifferences `
                    -Desired $desiredValue `
                    -Deployed $deployedValue `
                    -Path "$Path[$name]"
            }
            return
        }

        $allValues = @($desiredArray) + @($deployedArray)
        $nonScalarValues = @($allValues | Where-Object {
            $null -ne $_ -and
            $_ -isnot [string] -and
            $_ -isnot [decimal] -and
            $_ -isnot [DateTime] -and
            $_ -isnot [DateTimeOffset] -and
            $_ -isnot [Guid] -and
            -not $_.GetType().IsPrimitive
        })
        if ($nonScalarValues.Count -eq 0) {
            foreach ($value in $deployedArray) {
                if (@($desiredArray | Where-Object { [object]::Equals($_, $value) }).Count -eq 0) {
                    [pscustomobject]@{ path = "$Path[]"; change = 'Remove'; oldValue = $value; newValue = $null }
                }
            }
            foreach ($value in $desiredArray) {
                if (@($deployedArray | Where-Object { [object]::Equals($_, $value) }).Count -eq 0) {
                    [pscustomobject]@{ path = "$Path[]"; change = 'Add'; oldValue = $null; newValue = $value }
                }
            }
            return
        }

        $maximumCount = [Math]::Max($desiredArray.Count, $deployedArray.Count)
        for ($index = 0; $index -lt $maximumCount; $index++) {
            $desiredValue = $null
            if ($index -lt $desiredArray.Count) {
                $desiredValue = $desiredArray[$index]
            }
            $deployedValue = $null
            if ($index -lt $deployedArray.Count) {
                $deployedValue = $deployedArray[$index]
            }
            Get-FpacObjectDifferences `
                -Desired $desiredValue `
                -Deployed $deployedValue `
                -Path "$Path[$index]"
        }
        return
    }

    [pscustomobject]@{ path = $Path; change = 'Replace'; oldValue = $Deployed; newValue = $Desired }
}
