function New-FpacMaterializedPolicySets {
    param (
        [Parameter(Mandatory)]
        [System.Collections.IDictionary] $Assignments,

        [Parameter(Mandatory)]
        [System.Collections.IDictionary] $PolicySetDefinitions,

        [Parameter(Mandatory)]
        [System.Collections.IDictionary] $PolicyDefinitions,

        [Parameter()]
        [string] $PacOwnerId,

        [Parameter()]
        [System.Collections.IDictionary] $WorkspaceMap = @{},

        [Parameter()]
        [System.Collections.IDictionary] $CapacityMap = @{}
    )

    $materialized = [ordered]@{}
    foreach ($assignment in $Assignments.Values) {
        $policySetName = [string] $assignment.properties.policySetName
        if (-not $PolicySetDefinitions.Contains($policySetName)) {
            throw "Deployment '$($assignment.name)' references missing Policy Set definition '$policySetName'."
        }

        $policySet = $PolicySetDefinitions[$policySetName] |
            ConvertTo-Json -Depth 100 |
            ConvertFrom-Json -ErrorAction Stop
        foreach ($policyReference in @($policySet.properties.policies)) {
            if (@($policyReference.parameters.PSObject.Properties).Count -gt 0) {
                throw "Policy Set definition '$policySetName' contains parameter values for policy '$($policyReference.name)'. Put all concrete parameter values in the deployment assignment."
            }
        }
        $assignmentParameters = Get-FabricPropertyValue -InputObject $assignment.properties -Name 'parameters'
        $parameterProperties = if ($null -eq $assignmentParameters) {
            @()
        }
        else {
            @($assignmentParameters.PSObject.Properties)
        }
        foreach ($policyOverride in $parameterProperties) {
            $matchingReferences = @($policySet.properties.policies | Where-Object {
                [string]::Equals([string] $_.name, $policyOverride.Name, [System.StringComparison]::OrdinalIgnoreCase)
            })
            if ($matchingReferences.Count -ne 1 -or -not $PolicyDefinitions.Contains($policyOverride.Name)) {
                throw "Deployment '$($assignment.name)' parameter overrides reference missing policy definition '$($policyOverride.Name)'."
            }
            foreach ($parameter in @($policyOverride.Value.PSObject.Properties)) {
                $definitionParameter = $PolicyDefinitions[$policyOverride.Name].properties.parameters.PSObject.Properties[$parameter.Name]
                if ($null -eq $definitionParameter) {
                    throw "Deployment '$($assignment.name)' overrides missing parameter '$($parameter.Name)' on policy definition '$($policyOverride.Name)'."
                }
                $parameterMetadata = Get-FabricPropertyValue -InputObject $definitionParameter.Value -Name 'metadata'
                $targetProperty = [string] (Get-FabricPropertyValue -InputObject $parameterMetadata -Name 'targetProperty')
                $sourceValue = Get-FabricPropertyValue -InputObject $parameter.Value -Name 'value'
                $resolvedValues = foreach ($value in @($sourceValue)) {
                    Resolve-FpacParameterValue -Value $value `
                        -TargetProperty $targetProperty `
                        -WorkspaceMap $WorkspaceMap `
                        -CapacityMap $CapacityMap
                }
                $resolvedValue = if ([string] $definitionParameter.Value.type -eq 'Array') {
                    @($resolvedValues)
                }
                else {
                    @($resolvedValues)[0]
                }
                $matchingReferences[0].parameters |
                    Add-Member -NotePropertyName $parameter.Name `
                        -NotePropertyValue ([pscustomobject]@{ value = $resolvedValue }) -Force
            }
        }

        $effectivePolicySet = Resolve-FpacPolicySetEffectiveParameters `
            -PolicySet $policySet `
            -PolicyDefinitions $PolicyDefinitions
        $policies = [System.Collections.Generic.List[object]]::new()
        $policyDisplayNames = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
        foreach ($policyReference in @($effectivePolicySet.properties.policies)) {
            $definitionName = [string] $policyReference.name
            if (-not $PolicyDefinitions.Contains($definitionName)) {
                throw "Policy Set definition '$policySetName' references missing policy definition '$definitionName'."
            }
            $definition = $PolicyDefinitions[$definitionName] |
                ConvertTo-Json -Depth 100 |
                ConvertFrom-Json -ErrorAction Stop
            $displayName = [string] $definition.properties.displayName
            if (-not $policyDisplayNames.Add($displayName)) {
                throw "Policy Set deployment '$($assignment.name)' contains more than one policy named '$displayName'."
            }
            foreach ($parameter in @($definition.properties.parameters.PSObject.Properties)) {
                $effectiveValue = $policyReference.parameters.PSObject.Properties[$parameter.Name]
                if ($null -ne $effectiveValue) {
                    $parameter.Value |
                        Add-Member -NotePropertyName defaultValue `
                            -NotePropertyValue $effectiveValue.Value.value -Force
                }
            }
            $definitionMetadata = Get-FabricPropertyValue -InputObject $definition -Name 'metadata'
            $policies.Add([pscustomobject] [ordered]@{
                name       = $displayName
                metadata   = [pscustomobject] [ordered]@{
                    fpacId     = $definitionName
                }
                definition = $definition.properties
            })
        }

        $workspace = [string] (Get-FabricPropertyValue -InputObject $assignment.properties -Name 'workspace')
        if ([string]::IsNullOrWhiteSpace($workspace)) {
            throw "Policy Set deployment '$($assignment.name)' does not specify a workspace."
        }
        $displayName = [string] (Get-FabricPropertyValue -InputObject $assignment.properties -Name 'displayName')
        if ([string]::IsNullOrWhiteSpace($displayName)) {
            $displayName = [string] $assignment.name
        }
        $materializedName = ConvertTo-FpacIdentifier -DisplayName "$workspace-$displayName"
        if ($materialized.Contains($materializedName)) {
            throw "More than one Policy Set deployment resolves to '$workspace/$displayName'."
        }
        $policySetMetadata = Get-FabricPropertyValue -InputObject $policySet -Name 'metadata'
        $artifactOwner = [string] (Get-FabricPropertyValue -InputObject $policySetMetadata -Name 'pacOwnerId')
        if ([string]::IsNullOrWhiteSpace($artifactOwner)) {
            $artifactOwner = $PacOwnerId
        }
        $artifactId = [string] (Get-FabricPropertyValue -InputObject $policySetMetadata -Name 'fpacId')
        if ([string]::IsNullOrWhiteSpace($artifactId)) {
            $artifactId = [string] $assignment.name
        }
        $policySetDescription = [string] (Get-FabricPropertyValue -InputObject $policySet.properties -Name 'description')
        $materialized[$materializedName] = [ordered]@{
            name     = $materializedName
            metadata = [pscustomobject] [ordered]@{
                pacOwnerId = $artifactOwner
                fpacId     = $artifactId
            }
            properties = [pscustomobject] [ordered]@{
                displayName = $displayName
                description = $policySetDescription
                workspace = $workspace
                scope = $assignment.properties.scope
                status = $assignment.properties.status
                policies = @($policies.ToArray())
            }
        }
    }
    Assert-FpacActivePolicySetScopes -PolicySets $materialized
    return $materialized
}
