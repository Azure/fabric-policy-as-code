function New-FpacActivationChanges {
    param (
        [Parameter(Mandatory)]
        [System.Collections.IDictionary] $Desired,

        [Parameter(Mandatory)]
        [System.Collections.IDictionary] $Deployed
    )

    $changes = [System.Collections.Generic.List[object]]::new()
    foreach ($desiredPolicySet in $Desired.Values) {
        $desiredStatus = [string] $desiredPolicySet.properties.status
        $scopeKey = Get-FpacScopeKey -Scope $desiredPolicySet.properties.scope
        $current = @($Deployed.Values | Where-Object {
            [string] $_.properties.status -eq 'Active' -and
            (Get-FpacScopeKey -Scope $_.properties.scope) -eq $scopeKey
        })
        if ($current.Count -gt 1) {
            throw "Fabric returned more than one active Policy Set for scope '$scopeKey'."
        }
        $isCurrentDesired = $current.Count -eq 1 -and
            [string]::Equals(
                [string] $current[0].name,
                [string] $desiredPolicySet.name,
                [System.StringComparison]::OrdinalIgnoreCase
            )

        if ($desiredStatus -ne 'Active' -and
            ($desiredStatus -ne 'Inactive' -or -not $isCurrentDesired)) {
            continue
        }

        $expectedCurrent = if ($current.Count -eq 1) {
            [ordered]@{
                name         = [string] $current[0].name
                workspace    = [string] $current[0].properties.workspace
                displayName  = [string] $current[0].properties.displayName
                pacOwnerId   = [string] (Get-FabricPropertyValue -InputObject $current[0].metadata -Name 'pacOwnerId')
            }
        }
        else {
            $null
        }
        $changes.Add([ordered]@{
            scopeKey       = $scopeKey
            action         = if ($desiredStatus -eq 'Inactive') {
                'Deactivate'
            }
            elseif ($isCurrentDesired) {
                'Maintain'
            }
            elseif ($current.Count -eq 1) {
                'Replace'
            }
            else {
                'Activate'
            }
            desired        = [ordered]@{
                name        = [string] $desiredPolicySet.name
                workspace   = [string] $desiredPolicySet.properties.workspace
                displayName = [string] $desiredPolicySet.properties.displayName
            }
            expectedCurrent = $expectedCurrent
        })
    }
    return @($changes.ToArray())
}
