function Build-FpacResourcePlan {
    param (
        [Parameter(Mandatory)]
        [string] $ResourceType,

        [Parameter(Mandatory)]
        [System.Collections.IDictionary] $Desired,

        [Parameter(Mandatory)]
        [System.Collections.IDictionary] $Deployed,

        [Parameter()]
        [System.Collections.IDictionary] $DesiredComparison,

        [Parameter()]
        [System.Collections.IDictionary] $DeployedComparison,

        [Parameter()]
        [string[]] $ReplacementFields = @(),

        [Parameter()]
        [string] $PacOwnerId,

        [Parameter()]
        [ValidateSet('OwnedOnly', 'Full')]
        [string] $DesiredStateStrategy = 'OwnedOnly'
    )

    Write-FpacModernSection -Title "Processing $ResourceType"
    if ($null -eq $DesiredComparison) {
        $DesiredComparison = $Desired
    }
    if ($null -eq $DeployedComparison) {
        $DeployedComparison = $Deployed
    }
    $plan = New-FpacPlanBucket
    foreach ($name in @($Desired.Keys) | Sort-Object) {
        $desiredArtifact = $Desired[$name]
        if (-not $Deployed.Contains($name)) {
            $plan.new[$name] = $desiredArtifact
            Write-FpacModernStatus -Message "New: $name" -Status success
            continue
        }

        $deployedArtifact = $Deployed[$name]
        $desiredComparisonArtifact = $DesiredComparison[$name]
        $deployedComparisonArtifact = $DeployedComparison[$name]
        $changedFields = @(Get-FpacChangedFields -Desired $desiredComparisonArtifact.properties -Deployed $deployedComparisonArtifact.properties)
        $deployedMetadata = Get-FabricPropertyValue -InputObject $deployedArtifact -Name 'metadata'
        $deployedOwner = [string] (Get-FabricPropertyValue -InputObject $deployedMetadata -Name 'pacOwnerId')
        if (-not [string]::IsNullOrWhiteSpace($PacOwnerId) -and
            -not [string]::Equals($deployedOwner, $PacOwnerId, [System.StringComparison]::OrdinalIgnoreCase)) {
            if (-not [string]::IsNullOrWhiteSpace($deployedOwner)) {
                throw "$ResourceType resource '$name' is owned by '$deployedOwner', not configured PAC owner '$PacOwnerId'."
            }
            $plan.adopt[$name] = [ordered]@{
                name        = $name
                changes     = @('ownership') + $changedFields
                differences = @(
                    [ordered]@{
                        path     = 'metadata.pacOwnerId'
                        change   = 'Adopt'
                        oldValue = if ([string]::IsNullOrWhiteSpace($deployedOwner)) { $null } else { $deployedOwner }
                        newValue = $PacOwnerId
                    }
                ) + @(Get-FpacObjectDifferences -Desired $desiredComparisonArtifact.properties `
                    -Deployed $deployedComparisonArtifact.properties -Path 'properties')
                desired     = $desiredArtifact
                deployed    = $deployedArtifact
            }
            Write-FpacModernStatus -Message "Adopt: $name" -Status warning
            continue
        }
        if ($changedFields.Count -eq 0) {
            $plan.numberUnchanged++
            Write-FpacModernStatus -Message "Unchanged: $name" -Status info
            continue
        }

        $requiresReplacement = @($changedFields | Where-Object { $_ -in $ReplacementFields }).Count -gt 0
        if ($requiresReplacement -and $changedFields -contains 'scope') {
            $desiredScopeType = [string] $desiredComparisonArtifact.properties.scope.type
            $deployedScopeType = [string] $deployedComparisonArtifact.properties.scope.type
            if ([string]::Equals($desiredScopeType, $deployedScopeType, [System.StringComparison]::OrdinalIgnoreCase)) {
                $requiresReplacement = @($changedFields | Where-Object {
                    $_ -in $ReplacementFields -and $_ -ne 'scope'
                }).Count -gt 0
            }
        }
        $action = if ($requiresReplacement) { 'replace' } else { 'update' }
        $status = if ($requiresReplacement) { 'warning' } else { 'update' }
        $plan[$action][$name] = [ordered]@{
            name       = $name
            changes    = $changedFields
            differences = @(Get-FpacObjectDifferences -Desired $desiredComparisonArtifact.properties `
                -Deployed $deployedComparisonArtifact.properties -Path 'properties')
            desired    = $desiredArtifact
            deployed   = $deployedArtifact
        }
        Write-FpacModernStatus -Message "$($action.Substring(0, 1).ToUpperInvariant())$($action.Substring(1)) ($($changedFields -join ', ')): $name" -Status $status
    }

    foreach ($name in @($Deployed.Keys) | Sort-Object) {
        if (-not $Desired.Contains($name)) {
            if ($DesiredStateStrategy -eq 'OwnedOnly' -and -not [string]::IsNullOrWhiteSpace($PacOwnerId)) {
                $deployedMetadata = Get-FabricPropertyValue -InputObject $Deployed[$name] -Name 'metadata'
                $deployedOwner = [string] (Get-FabricPropertyValue -InputObject $deployedMetadata -Name 'pacOwnerId')
                if (-not [string]::Equals($deployedOwner, $PacOwnerId, [System.StringComparison]::OrdinalIgnoreCase)) {
                    Write-FpacModernStatus -Message "Unmanaged: $name" -Status info
                    continue
                }
            }
            $plan.delete[$name] = $Deployed[$name]
            Write-FpacModernStatus -Message "Delete: $name" -Status error
        }
    }

    $plan.numberOfChanges = $plan.new.Count + $plan.update.Count + $plan.replace.Count + $plan.adopt.Count + $plan.delete.Count
    return $plan
}
