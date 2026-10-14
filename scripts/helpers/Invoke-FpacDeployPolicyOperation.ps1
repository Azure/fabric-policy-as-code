function Invoke-FpacDeployPolicyOperation {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    param (
        [Parameter(Mandatory)]
        [string] $PlanFile,

        [Parameter(Mandatory)]
        [string] $GlobalSettingsPath,

        [Parameter()]
        [string] $EnvironmentName,

        [Parameter(Mandatory)]
        [string] $SchemaPath,

        [Parameter(Mandatory)]
        [ValidateRange(1, 10)]
        [int] $MaxRetryAttempts,

        [Parameter()]
        [ValidateRange(1, 7200)]
        [int] $OperationTimeoutSeconds = 1800,

        [Parameter()]
        [switch] $AllowActivationReplacement,

        [Parameter()]
        [switch] $AdoptUnowned
    )

    $script:MaxRetryAttempts = $MaxRetryAttempts
    $Global:fpacInfoStream = [System.Collections.Generic.List[string]]::new()
    $timer = [System.Diagnostics.Stopwatch]::StartNew()
    $plan = Read-FpacDeploymentPlan -Path $PlanFile -SchemaPath $SchemaPath
    $settings = Get-FpacGlobalSettings -Path $GlobalSettingsPath
    $selectedName = if ([string]::IsNullOrWhiteSpace($EnvironmentName)) {
        [string] $plan.environment.name
    }
    else {
        $EnvironmentName
    }
    $target = Select-FpacEnvironment -Environments $settings.Environments -EnvironmentName $selectedName

    if (-not [string]::Equals([string] $plan.environment.name, $target.Name, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Deployment plan environment '$($plan.environment.name)' does not match selected environment '$($target.Name)'."
    }
    if (-not [string]::Equals([string] $plan.environment.tenantId, $target.TenantId, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Deployment plan tenant '$($plan.environment.tenantId)' does not match configured tenant '$($target.TenantId)'."
    }
    if ([string] $plan.pacOwnerId -ne $settings.PacOwnerId) {
        throw "Deployment plan owner '$($plan.pacOwnerId)' does not match configured PAC owner '$($settings.PacOwnerId)'."
    }
    $planStrategy = [string] (Get-FabricPropertyValue -InputObject $plan -Name 'desiredStateStrategy')
    if (-not [string]::IsNullOrWhiteSpace($planStrategy) -and $planStrategy -ne $settings.DesiredStateStrategy) {
        throw "Deployment plan strategy '$planStrategy' does not match configured strategy '$($settings.DesiredStateStrategy)'."
    }
    if ($plan.numberOfChanges -eq 0) {
        throw 'The FPAC deployment plan contains no changes.'
    }

    Write-FpacModernHeader -Title 'Fabric Policy as Code (FPAC)' -Subtitle 'Deploying Policy Sets' -HeaderColor Magenta -SubtitleColor Magenta
    Write-FpacModernSection -Title 'Deployment Configuration'
    Write-FpacModernStatus -Message "FPAC Environment: $($target.Name)" -Status info
    Write-FpacModernStatus -Message "Plan: $([System.IO.Path]::GetFullPath($PlanFile))" -Status info
    Write-FpacModernStatus -Message "Tenant ID: $($target.TenantId)" -Status info
    Write-FpacModernStatus -Message "Planned changes: $($plan.numberOfChanges)" -Status info

    $headers = Get-FabricAuthenticationHeaders -TenantId $target.TenantId
    $inventory = Get-FpacDeploymentInventory -Headers $headers
    $activationChanges = @(Get-FabricPropertyValue -InputObject $plan -Name 'activationChanges')
    $activationReplacementCount = Assert-FpacActivationChangesCurrent `
        -ActivationChanges $activationChanges `
        -Inventory $inventory
    if ($activationReplacementCount -gt 0 -and -not $AllowActivationReplacement) {
        throw "The plan replaces $activationReplacementCount active Policy Set(s). Review the activation changes and rerun with -AllowActivationReplacement."
    }
    $adoptionCount = @($plan.policySets.adopt.PSObject.Properties).Count
    if ($adoptionCount -gt 0 -and -not $AdoptUnowned) {
        throw "The plan contains $adoptionCount unowned Policy Set adoption(s). Review them and rerun with -AdoptUnowned."
    }
    $result = [ordered]@{
        Created  = 0
        Updated  = 0
        Replaced = 0
        Deleted  = 0
        Skipped  = 0
        Adopted  = 0
    }

    Write-FpacModernSection -Title 'Applying Policy Set Changes'
    foreach ($name in @($plan.policySets.new.PSObject.Properties | ForEach-Object { $_.Name }) | Sort-Object) {
        $desired = $plan.policySets.new.$name
        $workspaceName = [string] $desired.properties.workspace
        $displayName = [string] $desired.properties.displayName
        if (-not $inventory.Contains($workspaceName)) {
            throw "Workspace '$workspaceName' was not returned by Fabric during deployment."
        }
        if ($null -ne (Resolve-FpacPolicySetItem -Inventory $inventory -PolicySet $desired -AllowMissing)) {
            throw "Policy Set '$displayName' already exists in workspace '$workspaceName'. The deployment plan may be stale."
        }
        if ($PSCmdlet.ShouldProcess("$workspaceName/$displayName", 'Create Fabric Policy Set')) {
            $replacesActive = @($activationChanges | Where-Object {
                $_.desired.name -eq $desired.name -and $_.action -eq 'Replace'
            }).Count -gt 0
            $null = New-FabricPolicySet -PolicySet $desired -WorkspaceId $inventory[$workspaceName].Id `
                -Headers $headers -OperationTimeoutSeconds $OperationTimeoutSeconds `
                -AllowActivationReplacement:$replacesActive
            $result.Created++
            Write-FpacModernStatus -Message "Created: $workspaceName/$displayName" -Status success
        }
        else {
            $result.Skipped++
        }
    }

    foreach ($name in @($plan.policySets.update.PSObject.Properties | ForEach-Object { $_.Name }) | Sort-Object) {
        $entry = $plan.policySets.update.$name
        $resolved = Resolve-FpacPolicySetItem -Inventory $inventory -PolicySet $entry.deployed
        $label = "$($resolved.WorkspaceName)/$($resolved.DisplayName)"
        if ($PSCmdlet.ShouldProcess($label, 'Update Fabric Policy Set')) {
            $replacesActive = @($activationChanges | Where-Object {
                $_.desired.name -eq $entry.desired.name -and $_.action -eq 'Replace'
            }).Count -gt 0
            Update-FabricPolicySet -PlanEntry $entry -ResolvedItem $resolved -Headers $headers `
                -OperationTimeoutSeconds $OperationTimeoutSeconds `
                -PacOwnerId $settings.PacOwnerId `
                -DesiredStateStrategy $settings.DesiredStateStrategy `
                -AllowActivationReplacement:$replacesActive
            $result.Updated++
            Write-FpacModernStatus -Message "Updated: $label" -Status update
        }
        else {
            $result.Skipped++
        }
    }

    foreach ($name in @($plan.policySets.replace.PSObject.Properties | ForEach-Object { $_.Name }) | Sort-Object) {
        $entry = $plan.policySets.replace.$name
        $resolved = Resolve-FpacPolicySetItem -Inventory $inventory -PolicySet $entry.deployed
        $oldLabel = "$($resolved.WorkspaceName)/$($resolved.DisplayName)"
        $newWorkspaceName = [string] $entry.desired.properties.workspace
        $newLabel = "$newWorkspaceName/$($entry.desired.properties.displayName)"
        if (-not $inventory.Contains($newWorkspaceName)) {
            throw "Workspace '$newWorkspaceName' was not returned by Fabric during deployment."
        }
        if ($PSCmdlet.ShouldProcess("$oldLabel -> $newLabel", 'Replace Fabric Policy Set')) {
            $sameStorageIdentity = [string]::Equals(
                $resolved.WorkspaceName,
                $newWorkspaceName,
                [System.StringComparison]::OrdinalIgnoreCase
            ) -and [string]::Equals(
                $resolved.DisplayName,
                [string] $entry.desired.properties.displayName,
                [System.StringComparison]::OrdinalIgnoreCase
            )
            if ($sameStorageIdentity) {
                Remove-FabricPolicySet -PolicySet $entry.deployed -ResolvedItem $resolved -Headers $headers
                $null = New-FabricPolicySet -PolicySet $entry.desired -WorkspaceId $inventory[$newWorkspaceName].Id `
                    -Headers $headers -OperationTimeoutSeconds $OperationTimeoutSeconds `
                    -AllowActivationReplacement:$AllowActivationReplacement
            }
            else {
                $newPolicySetId = New-FabricPolicySet -PolicySet $entry.desired `
                    -WorkspaceId $inventory[$newWorkspaceName].Id `
                    -Headers $headers -OperationTimeoutSeconds $OperationTimeoutSeconds `
                    -DeferActivation
                if ([string] $entry.desired.properties.status -eq 'Active') {
                    Set-FabricPolicySetStatus -WorkspaceId $inventory[$newWorkspaceName].Id `
                        -PolicySetId $newPolicySetId `
                        -Scope $entry.desired.properties.scope `
                        -DesiredStatus Active -CurrentStatus Inactive `
                        -Headers $headers -AllowReplace
                }
                $skipOldDeactivation = [string] $entry.deployed.properties.status -eq 'Active' -and
                    [string] $entry.desired.properties.status -eq 'Active' -and
                    (Get-FpacScopeKey -Scope $entry.deployed.properties.scope) -eq
                        (Get-FpacScopeKey -Scope $entry.desired.properties.scope)
                Remove-FabricPolicySet -PolicySet $entry.deployed -ResolvedItem $resolved `
                    -Headers $headers -SkipDeactivation:$skipOldDeactivation
            }
            $result.Replaced++
            Write-FpacModernStatus -Message "Replaced: $oldLabel -> $newLabel" -Status warning
        }
        else {
            $result.Skipped++
        }
    }

    foreach ($name in @($plan.policySets.adopt.PSObject.Properties | ForEach-Object { $_.Name }) | Sort-Object) {
        $entry = $plan.policySets.adopt.$name
        $resolved = Resolve-FpacPolicySetItem -Inventory $inventory -PolicySet $entry.deployed
        $label = "$($resolved.WorkspaceName)/$($resolved.DisplayName)"
        if ($PSCmdlet.ShouldProcess($label, "Adopt Fabric Policy Set into PAC owner '$($settings.PacOwnerId)'")) {
            Set-FabricPolicySetOwnership -PolicySet $entry.desired -ResolvedItem $resolved `
                -PacOwnerId $settings.PacOwnerId -Headers $headers
            Update-FabricPolicySet -PlanEntry $entry -ResolvedItem $resolved -Headers $headers `
                -OperationTimeoutSeconds $OperationTimeoutSeconds `
                -PacOwnerId $settings.PacOwnerId `
                -DesiredStateStrategy $settings.DesiredStateStrategy `
                -AdoptUnowned `
                -AllowActivationReplacement:$AllowActivationReplacement
            $result.Adopted++
            Write-FpacModernStatus -Message "Adopted: $label" -Status warning
        }
        else {
            $result.Skipped++
        }
    }

    foreach ($name in @($plan.policySets.delete.PSObject.Properties | ForEach-Object { $_.Name }) | Sort-Object) {
        $deployed = $plan.policySets.delete.$name
        $resolved = Resolve-FpacPolicySetItem -Inventory $inventory -PolicySet $deployed
        $label = "$($resolved.WorkspaceName)/$($resolved.DisplayName)"
        if ($PSCmdlet.ShouldProcess($label, 'Delete Fabric Policy Set')) {
            Remove-FabricPolicySet -PolicySet $deployed -ResolvedItem $resolved -Headers $headers
            $result.Deleted++
            Write-FpacModernStatus -Message "Deleted: $label" -Status error
        }
        else {
            $result.Skipped++
        }
    }

    $timer.Stop()
    Write-FpacModernHeader -Title 'FPAC Deployment Complete' -Subtitle 'Policy Set deployment finished' -HeaderColor Green -SubtitleColor DarkGreen
    Write-FpacModernStatus -Message "Created: $($result.Created)" -Status success
    Write-FpacModernStatus -Message "Updated: $($result.Updated)" -Status update
    Write-FpacModernStatus -Message "Replaced: $($result.Replaced)" -Status warning
    Write-FpacModernStatus -Message "Adopted: $($result.Adopted)" -Status warning
    Write-FpacModernStatus -Message "Deleted: $($result.Deleted)" -Status error
    Write-FpacModernStatus -Message "Skipped: $($result.Skipped)" -Status skip
    Write-FpacModernStatus -Message "Execution time: $($timer.Elapsed.ToString('mm\:ss\.fff'))" -Status success
    if ($result.Created + $result.Updated + $result.Replaced + $result.Adopted -gt 0) {
        Write-FpacModernStatus -Message 'Activation requests were accepted; Fabric enforcement can take up to 15 minutes to propagate.' -Status info
    }

    return [pscustomobject] $result
}
