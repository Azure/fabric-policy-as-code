function Assert-FpacDeploymentWorkspaces {
    param (
        [Parameter(Mandatory)]
        [System.Collections.IDictionary] $Assignments,

        [Parameter(Mandatory)]
        [System.Collections.IDictionary] $WorkspaceMap,

        [Parameter()]
        [System.Collections.IDictionary] $WorkspaceDetails
    )

    foreach ($assignment in $Assignments.Values) {
        $workspace = [string] (Get-FabricPropertyValue -InputObject $assignment.properties -Name 'workspace')
        if (-not $WorkspaceMap.Contains($workspace)) {
            throw "Workspace '$workspace' targeted by Policy Set deployment '$($assignment.name)' was not returned by Fabric. Verify the workspace name and access for the planning identity."
        }
        if ($null -ne $WorkspaceDetails -and $WorkspaceDetails.Contains($workspace)) {
            $capacityId = [string] (Get-FabricPropertyValue -InputObject $WorkspaceDetails[$workspace] -Name 'CapacityId')
            if ([string]::IsNullOrWhiteSpace($capacityId)) {
                throw "Workspace '$workspace' targeted by Policy Set deployment '$($assignment.name)' is not assigned to a Fabric capacity. Policy Sets can only be stored in capacity-backed workspaces."
            }
        }
    }
}
