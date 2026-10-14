function Assert-FpacAssignmentsWithinEnvironment {
    param (
        [Parameter(Mandatory)]
        [System.Collections.IDictionary] $Assignments,

        [Parameter(Mandatory)]
        [pscustomobject] $Target
    )

    if ($Target.ScopeType -ne 'Capacity') {
        return
    }

    foreach ($assignment in $Assignments.Values) {
        $scope = $assignment.properties.scope
        $scopeType = [string] (Get-FabricPropertyValue -InputObject $scope -Name 'type')
        $capacityId = [string] (Get-FabricPropertyValue -InputObject $scope -Name 'id')
        if ($scopeType -ne 'Capacity' -or $capacityId -notin @($Target.CapacityIds)) {
            throw "Assignment '$($assignment.name)' targets $scopeType scope '$capacityId', which is outside capacity environment '$($Target.Name)'."
        }
    }
}
