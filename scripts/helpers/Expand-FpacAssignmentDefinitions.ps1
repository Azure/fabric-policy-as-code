function Expand-FpacAssignmentDefinitions {
    param (
        [Parameter(Mandatory)]
        [System.Collections.IDictionary] $AssignmentDefinitions,

        [Parameter(Mandatory)]
        [string] $EnvironmentName,

        [Parameter()]
        [System.Collections.IDictionary] $CapacityMap = @{}
    )

    $expanded = [ordered]@{}
    foreach ($definitionName in @($AssignmentDefinitions.Keys) | Sort-Object) {
        $definition = $AssignmentDefinitions[$definitionName]
        $childrenProperty = $definition.properties.PSObject.Properties['children']
        if ($null -eq $childrenProperty) {
            $targetsProperty = $definition.properties.PSObject.Properties['targets']
            if ($null -eq $targetsProperty) {
                if ([string]::Equals(
                    [string] $definition.properties.environment,
                    $EnvironmentName,
                    [System.StringComparison]::OrdinalIgnoreCase
                )) {
                    $expanded[$definitionName] = $definition
                }
                continue
            }
            $children = @([pscustomobject]@{
                name = [string] $definition.name
                displayName = [string] $definition.properties.displayName
                status = Get-FabricPropertyValue -InputObject $definition.properties -Name 'status'
                parameters = Get-FabricPropertyValue -InputObject $definition.properties -Name 'parameters'
                targets = $targetsProperty.Value
            })
        }
        else {
            $children = @($childrenProperty.Value)
        }

        foreach ($child in $children) {
            $environmentProperty = $child.targets.PSObject.Properties |
                Where-Object { [string]::Equals($_.Name, $EnvironmentName, [System.StringComparison]::OrdinalIgnoreCase) } |
                Select-Object -First 1
            if ($null -eq $environmentProperty) {
                continue
            }

            $targets = @($environmentProperty.Value)
            for ($targetIndex = 0; $targetIndex -lt $targets.Count; $targetIndex++) {
                $target = $targets[$targetIndex]
                $workspace = [string] (Get-FabricPropertyValue -InputObject $target -Name 'workspace')
                if ([string]::IsNullOrWhiteSpace($workspace)) {
                    throw "Policy Set deployment definition '$definitionName' contains a target without a workspace."
                }
                $scope = Get-FabricPropertyValue -InputObject $target -Name 'scope'
                if ($null -eq $scope) {
                    throw "Policy Set deployment definition '$definitionName' contains a target without a scope."
                }
                $resolvedScope = Resolve-FpacAssignmentScope -Scope $scope -CapacityMap $CapacityMap
                $assignmentName = [string] $child.name
                if ($targets.Count -gt 1) {
                    $scopeNameValue = Get-FabricPropertyValue -InputObject $scope -Name 'name'
                    $scopeName = if (-not [string]::IsNullOrWhiteSpace([string] $scopeNameValue)) {
                        [string] $scopeNameValue
                    }
                    elseif ([string] $resolvedScope.type -eq 'Tenant') {
                        'tenant'
                    }
                    else {
                        [string] $resolvedScope.id
                    }
                    $assignmentName = ConvertTo-FpacIdentifier -DisplayName "$assignmentName-$workspace-$scopeName"
                }
                if ($expanded.Contains($assignmentName)) {
                    throw "Policy Set deployment definition '$definitionName' produces duplicate instance name '$assignmentName'."
                }

                $childStatus = Get-FabricPropertyValue -InputObject $child -Name 'status'
                $definitionStatus = Get-FabricPropertyValue -InputObject $definition.properties -Name 'status'
                $status = if (-not [string]::IsNullOrWhiteSpace([string] $childStatus)) {
                    [string] $childStatus
                }
                elseif (-not [string]::IsNullOrWhiteSpace([string] $definitionStatus)) {
                    [string] $definitionStatus
                }
                else {
                    'Active'
                }
                $parameters = if ($null -ne $child.PSObject.Properties['parameters']) {
                    $child.parameters
                }
                else {
                    [pscustomobject]@{}
                }
                $childDisplayName = [string] (Get-FabricPropertyValue -InputObject $child -Name 'displayName')
                $displayName = if (-not [string]::IsNullOrWhiteSpace($childDisplayName)) {
                    $childDisplayName
                }
                else {
                    [string] $child.name
                }
                $expanded[$assignmentName] = [pscustomobject]@{
                    '$schema' = $definition.'$schema'
                    name = $assignmentName
                    properties = [pscustomobject]@{
                        environment = $EnvironmentName
                        policySetName = [string] $definition.properties.policySetName
                        displayName = $displayName
                        workspace = $workspace
                        scope = $resolvedScope
                        status = $status
                        parameters = $parameters
                    }
                }
            }
        }
    }
    return $expanded
}
