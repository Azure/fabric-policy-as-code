function Assert-FpacAssignmentsWithinEnvironment {
    param (
        [Parameter(Mandatory)]
        [System.Collections.IDictionary] $Assignments,

        [Parameter(Mandatory)]
        [pscustomobject] $Target
    )

    foreach ($assignment in $Assignments.Values) {
        $scope = $assignment.properties.scope
        $scopeType = [string] (Get-FabricPropertyValue -InputObject $scope -Name 'type')
        $capacityId = [string] (Get-FabricPropertyValue -InputObject $scope -Name 'id')
        if (-not (Test-FpacScopeWithinEnvironment -Scope $scope -Target $Target)) {
            throw "Assignment '$($assignment.name)' targets $scopeType scope '$capacityId', which is outside $($Target.ScopeType.ToLowerInvariant()) environment '$($Target.Name)'."
        }
    }
}
