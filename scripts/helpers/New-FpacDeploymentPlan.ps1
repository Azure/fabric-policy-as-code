function New-FpacDeploymentPlan {
    param (
        [Parameter(Mandatory)]
        [string] $DesiredRoot,

        [Parameter(Mandatory)]
        [string] $DeployedRoot,

        [Parameter(Mandatory)]
        [pscustomobject] $Target,

        [Parameter(Mandatory)]
        [string] $SchemaReference,

        [Parameter()]
        [System.Collections.IDictionary] $CapacityMap = @{},

        [Parameter()]
        [System.Collections.IDictionary] $WorkspaceMap,

        [Parameter()]
        [System.Collections.IDictionary] $WorkspaceDetails,

        [Parameter()]
        [string] $PacOwnerId = '',

        [Parameter()]
        [ValidateSet('OwnedOnly', 'Full')]
        [string] $DesiredStateStrategy = 'OwnedOnly',

        [Parameter()]
        [object[]] $Environments,

        [Parameter()]
        [switch] $DetailedOutput
    )

    $allDesiredDefinitions = Get-FpacArtifactCollection -Path (Join-Path $DesiredRoot 'policyDefinitions')
    $deployedDefinitions = Get-FpacArtifactCollection -Path (Join-Path $DeployedRoot 'policyDefinitions')
    $allDesiredPolicySets = Get-FpacArtifactCollection -Path (Join-Path $DesiredRoot 'policySetDefinitions')
    $deployedPolicySets = Get-FpacArtifactCollection -Path (Join-Path $DeployedRoot 'policySets')
    $allDesiredAssignmentDefinitions = Get-FpacArtifactCollection -Path (Join-Path $DesiredRoot 'policyAssignments')
    $allDeployedAssignmentDefinitions = Get-FpacArtifactCollection -Path (Join-Path $DeployedRoot 'assignments')
    foreach ($artifact in @($allDesiredDefinitions.Values) + @($allDesiredPolicySets.Values)) {
        $metadata = Get-FabricPropertyValue -InputObject $artifact -Name 'metadata'
        $artifactOwner = [string] (Get-FabricPropertyValue -InputObject $metadata -Name 'pacOwnerId')
        if (-not [string]::IsNullOrWhiteSpace($artifactOwner) -and
            -not [string]::Equals($artifactOwner, $PacOwnerId, [System.StringComparison]::OrdinalIgnoreCase)) {
            throw "FPAC artifact '$($artifact.name)' is owned by '$artifactOwner', not configured PAC owner '$PacOwnerId'."
        }
    }
    if ($null -ne $Environments -and $Environments.Count -gt 0) {
        Assert-FpacCrossEnvironmentActiveScopes `
            -AssignmentDefinitions $allDesiredAssignmentDefinitions `
            -Environments $Environments
    }

    $desiredAssignments = Expand-FpacAssignmentDefinitions `
        -AssignmentDefinitions $allDesiredAssignmentDefinitions `
        -EnvironmentName $Target.Name `
        -CapacityMap $CapacityMap
    Assert-FpacAssignmentsWithinEnvironment -Assignments $desiredAssignments -Target $Target
    if ($null -ne $WorkspaceMap) {
        Assert-FpacDeploymentWorkspaces -Assignments $desiredAssignments -WorkspaceMap $WorkspaceMap `
            -WorkspaceDetails $WorkspaceDetails
    }
    $deployedAssignments = Expand-FpacAssignmentDefinitions `
        -AssignmentDefinitions $allDeployedAssignmentDefinitions `
        -EnvironmentName $Target.Name `
        -CapacityMap $CapacityMap

    $desiredPolicySets = [ordered]@{}
    foreach ($assignment in $desiredAssignments.Values) {
        $policySetName = [string] $assignment.properties.policySetName
        if (-not $allDesiredPolicySets.Contains($policySetName)) {
            throw "Deployment '$($assignment.name)' references missing Policy Set definition '$policySetName'."
        }
        $desiredPolicySets[$policySetName] = $allDesiredPolicySets[$policySetName]
    }

    $desiredDefinitions = [ordered]@{}
    foreach ($policySet in $desiredPolicySets.Values) {
        foreach ($policyReference in @($policySet.properties.policies)) {
            $definitionName = [string] $policyReference.name
            if (-not $allDesiredDefinitions.Contains($definitionName)) {
                throw "Policy Set definition '$($policySet.name)' references missing policy definition '$definitionName'."
            }
            $desiredDefinitions[$definitionName] = $allDesiredDefinitions[$definitionName]
        }
    }

    $desiredConcretePolicySets = New-FpacMaterializedPolicySets `
        -Assignments $desiredAssignments `
        -PolicySetDefinitions $desiredPolicySets `
        -PolicyDefinitions $desiredDefinitions `
        -PacOwnerId $PacOwnerId `
        -WorkspaceMap $WorkspaceMap `
        -CapacityMap $CapacityMap
    $deployedConcretePolicySets = New-FpacMaterializedPolicySets `
        -Assignments $deployedAssignments `
        -PolicySetDefinitions $deployedPolicySets `
        -PolicyDefinitions $deployedDefinitions `
        -WorkspaceMap $WorkspaceMap `
        -CapacityMap $CapacityMap
    $deployedConcretePolicySets = Align-FpacPolicySetsByOwnership `
        -Desired $desiredConcretePolicySets `
        -Deployed $deployedConcretePolicySets
    $policySets = Build-FpacResourcePlan -ResourceType 'Policy Sets' `
        -Desired $desiredConcretePolicySets `
        -Deployed $deployedConcretePolicySets `
        -ReplacementFields @('workspace', 'scope') `
        -PacOwnerId $PacOwnerId `
        -DesiredStateStrategy $DesiredStateStrategy
    $activationChanges = New-FpacActivationChanges `
        -Desired $desiredConcretePolicySets `
        -Deployed $deployedConcretePolicySets

    return [ordered]@{
        '$schema'            = $SchemaReference
        createdOn            = [DateTime]::UtcNow.ToString('yyyy-MM-dd HH:mm:ssZ')
        pacOwnerId           = if ([string]::IsNullOrWhiteSpace($PacOwnerId)) {
            "fpac:$($Target.Name)"
        }
        else {
            $PacOwnerId
        }
        desiredStateStrategy = $DesiredStateStrategy
        environment          = [ordered]@{
            name       = $Target.Name
            tenantId   = $Target.TenantId
            scopes     = @($Target.Scopes | ForEach-Object {
                [ordered]@{
                    type = $_.Type
                    capacityId = $_.CapacityId
                }
            })
        }
        policySets           = $policySets
        activationChanges    = @($activationChanges)
        numberOfChanges      = $policySets.numberOfChanges
        numberUnchanged      = $policySets.numberUnchanged
    }
}
