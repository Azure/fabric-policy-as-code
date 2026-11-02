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
        [System.Collections.IDictionary] $CapacityMap = @{},

        [Parameter()]
        [System.Collections.IDictionary] $WorkspaceMap = @{}
    )

    if ($Action -eq 'Delete') {
        Write-FpacModernStatus -Message "Delete: $Name" -Status error -Indent 2
        return
    }
    Write-FpacModernStatus -Message "[$ResourceType] Detailed Changes for: $Name" -Status info -Indent 6
    if ($Action -eq 'New') {
        $displayProperties = ConvertTo-FpacPlanDisplayValue -Value $Desired.properties -WorkspaceMap $WorkspaceMap
        foreach ($line in (($displayProperties | ConvertTo-Json -Depth 100) -split '\r?\n')) {
            Write-FpacColoredOutput -Message "        + $line" -Color Green
        }
        return
    }
    if ($null -eq $Differences -or $Differences.Count -eq 0) {
        $Differences = @(Get-FpacObjectDifferences -Desired $Desired.properties -Deployed $Deployed.properties -Path 'properties')
    }
    foreach ($difference in $Differences) {
        $displayValues = @{}
        foreach ($side in @('old', 'new')) {
            $resource = if ($side -eq 'old') { $Deployed } else { $Desired }
            $targetProperty = ''
            if ($difference.path -eq 'properties.workspace') {
                $targetProperty = 'workspace.id'
            }
            elseif ($difference.path -match '^properties\.policies\[(.+)\]\.definition\.parameters\.(.+)\.defaultValue(?:\[\])?$') {
                $policyName = $Matches[1]
                $parameterName = $Matches[2]
                $properties = Get-FabricPropertyValue -InputObject $resource -Name 'properties'
                $policies = Get-FabricPropertyValue -InputObject $properties -Name 'policies'
                $policy = @($policies | Where-Object { $null -ne $_ -and $_.name -ceq $policyName }) | Select-Object -First 1
                $definition = Get-FabricPropertyValue -InputObject $policy -Name 'definition'
                $parameters = Get-FabricPropertyValue -InputObject $definition -Name 'parameters'
                $parameter = Get-FabricPropertyValue -InputObject $parameters -Name $parameterName
                $metadata = Get-FabricPropertyValue -InputObject $parameter -Name 'metadata'
                $targetProperty = [string] (Get-FabricPropertyValue -InputObject $metadata -Name 'targetProperty')
            }
            elseif ($difference.path -match '^properties\.policies\[(.+)\]\.definition\.conditions\[(\d+)\]\.predicate(?:\.values(?:\[\])?)?$') {
                $policyName = $Matches[1]
                $conditionIndex = [int] $Matches[2]
                $properties = Get-FabricPropertyValue -InputObject $resource -Name 'properties'
                $policies = Get-FabricPropertyValue -InputObject $properties -Name 'policies'
                $policy = @($policies | Where-Object { $null -ne $_ -and $_.name -ceq $policyName }) | Select-Object -First 1
                $definition = Get-FabricPropertyValue -InputObject $policy -Name 'definition'
                $conditions = @(Get-FabricPropertyValue -InputObject $definition -Name 'conditions')
                if ($conditionIndex -lt $conditions.Count) {
                    $targetProperty = [string] (Get-FabricPropertyValue -InputObject $conditions[$conditionIndex] -Name 'targetProperty')
                }
            }
            $displayValues[$side] = ConvertTo-FpacPlanDisplayValue -Value $difference."${side}Value" `
                -TargetProperty $targetProperty -WorkspaceMap $WorkspaceMap
        }
        $propertyLabel = Format-FpacPlanPropertyPath -Path $difference.path
        Write-FpacModernStatus -Message "Property: $propertyLabel" -Status info -Indent 8
        if ($difference.change -in @('Remove', 'Replace', 'Adopt')) {
            $oldValue = if ($displayValues.old -is [string]) {
                $displayValues.old
            }
            else {
                $displayValues.old | ConvertTo-Json -Depth 100 -Compress
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
            $newValue = if ($displayValues.new -is [string]) {
                $displayValues.new
            }
            else {
                $displayValues.new | ConvertTo-Json -Depth 100 -Compress
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
