function Assert-FpacActivationChangesCurrent {
    param (
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]] $ActivationChanges,

        [Parameter(Mandatory)]
        [System.Collections.IDictionary] $Inventory
    )

    $replacementCount = 0
    foreach ($change in $ActivationChanges) {
        $active = [System.Collections.Generic.List[object]]::new()
        foreach ($workspace in $Inventory.Values) {
            foreach ($policySet in $workspace.PolicySets.Values) {
                if ([string] $policySet.Status -eq 'Active' -and
                    (Get-FpacScopeKey -Scope $policySet.Scope) -eq [string] $change.scopeKey) {
                    $active.Add([pscustomobject]@{
                        Workspace   = [string] $workspace.Name
                        DisplayName = [string] $policySet.DisplayName
                    })
                }
            }
        }
        if ($active.Count -gt 1) {
            throw "Fabric returned more than one active Policy Set for scope '$($change.scopeKey)'."
        }
        $expected = Get-FabricPropertyValue -InputObject $change -Name 'expectedCurrent'
        if ($null -eq $expected) {
            if ($active.Count -gt 0) {
                throw "Deployment plan expected no active Policy Set for '$($change.scopeKey)', but Fabric now reports '$($active[0].Workspace)/$($active[0].DisplayName)'. Rebuild the plan."
            }
            continue
        }
        if ([string] $change.action -eq 'Replace') {
            $replacementCount++
        }
        if ($active.Count -eq 0 -or
            -not [string]::Equals([string] $active[0].Workspace, [string] $expected.workspace, [System.StringComparison]::OrdinalIgnoreCase) -or
            -not [string]::Equals([string] $active[0].DisplayName, [string] $expected.displayName, [System.StringComparison]::OrdinalIgnoreCase)) {
            $actual = if ($active.Count -eq 0) { 'none' } else { "$($active[0].Workspace)/$($active[0].DisplayName)" }
            throw "Deployment plan expected active Policy Set '$($expected.workspace)/$($expected.displayName)' for '$($change.scopeKey)', but Fabric now reports '$actual'. Rebuild the plan."
        }
    }
    return $replacementCount
}
