function Write-FpacDetailedChanges {
    param (
        [Parameter(Mandatory)]
        [string] $ResourceType,

        [Parameter(Mandatory)]
        [ValidateSet('New', 'Update', 'Replace', 'Adopt', 'Delete')]
        [string] $Action,

        [Parameter(Mandatory)]
        [string] $Name,

        [Parameter()]
        [AllowNull()]
        [object] $Desired,

        [Parameter()]
        [AllowNull()]
        [object] $Deployed,

        [Parameter()]
        [string[]] $ChangedFields = @(),

        [Parameter()]
        [object[]] $Differences = @(),

        [Parameter()]
        [System.Collections.IDictionary] $CapacityMap = @{}
    )

    if ($Action -eq 'Delete') {
        Write-FpacModernStatus -Message "Delete: $Name" -Status error -Indent 2
        return
    }
    Write-FpacModernStatus -Message "[$ResourceType] Detailed Changes for: $Name" -Status info -Indent 6
    if ($Action -eq 'New') {
        foreach ($line in (($Desired.properties | ConvertTo-Json -Depth 100) -split '\r?\n')) {
            Write-FpacColoredOutput -Message "        + $line" -Color Green
        }
        return
    }
    if ($null -eq $Differences -or $Differences.Count -eq 0) {
        $Differences = @(Get-FpacObjectDifferences -Desired $Desired.properties -Deployed $Deployed.properties -Path 'properties')
    }
    foreach ($difference in $Differences) {
        $propertyLabel = Format-FpacPlanPropertyPath -Path $difference.path
        Write-FpacModernStatus -Message "Property: $propertyLabel" -Status info -Indent 8
        if ($difference.change -in @('Remove', 'Replace', 'Adopt')) {
            $oldValue = if ($difference.oldValue -is [string]) {
                $difference.oldValue
            }
            else {
                $difference.oldValue | ConvertTo-Json -Depth 100 -Compress
            }
            if ($difference.path -match '(^|\.)metadata\.pacOwnerId$' -and
                [string]::IsNullOrWhiteSpace([string] $difference.oldValue)) {
                $oldValue = '(unowned)'
            }
            elseif ($difference.path -eq 'properties.scope.id' -and
                -not [string]::IsNullOrWhiteSpace([string] $difference.oldValue)) {
                $oldValue = Format-FpacScopeDisplayName -ScopeKey "Capacity:$($difference.oldValue)" -CapacityMap $CapacityMap
            }
            elseif ($null -eq $difference.oldValue) {
                $oldValue = '(not set)'
            }
            elseif ($difference.oldValue -is [string] -and $difference.oldValue.Length -eq 0) {
                $oldValue = '""'
            }
            Write-FpacColoredOutput -Message "          - $oldValue" -Color Red
        }
        if ($difference.change -in @('Add', 'Replace', 'Adopt')) {
            $newValue = if ($difference.newValue -is [string]) {
                $difference.newValue
            }
            else {
                $difference.newValue | ConvertTo-Json -Depth 100 -Compress
            }
            if ($difference.path -eq 'properties.scope.id' -and
                -not [string]::IsNullOrWhiteSpace([string] $difference.newValue)) {
                $newValue = Format-FpacScopeDisplayName -ScopeKey "Capacity:$($difference.newValue)" -CapacityMap $CapacityMap
            }
            elseif ($null -eq $difference.newValue) {
                $newValue = '(not set)'
            }
            elseif ($difference.newValue -is [string] -and $difference.newValue.Length -eq 0) {
                $newValue = '""'
            }
            Write-FpacColoredOutput -Message "          + $newValue" -Color Green
        }
    }
}
