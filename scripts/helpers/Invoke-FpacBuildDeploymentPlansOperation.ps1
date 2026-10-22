function Invoke-FpacBuildDeploymentPlansOperation {
    param (
        [Parameter(Mandatory)]
        [string] $DefinitionsPath,

        [Parameter(Mandatory)]
        [string] $OutputPath,

        [Parameter(Mandatory)]
        [string] $GlobalSettingsPath,

        [Parameter()]
        [string] $EnvironmentName,

        [Parameter()]
        [switch] $DetailedOutput,

        [Parameter()]
        [ValidateSet('none', 'ado', 'gitlab')]
        [string] $DevOpsType = 'none',

        [Parameter(Mandatory)]
        [ValidateRange(1, 10)]
        [int] $MaxRetryAttempts
    )

    $script:MaxRetryAttempts = $MaxRetryAttempts
    $Global:fpacInfoStream = [System.Collections.Generic.List[string]]::new()
    $timer = [System.Diagnostics.Stopwatch]::StartNew()
    $repositoryRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $settings = Get-FpacGlobalSettings -Path $GlobalSettingsPath
    $target = Select-FpacEnvironment -Environments $settings.Environments -EnvironmentName $EnvironmentName
    $desiredRoot = [System.IO.Path]::GetFullPath($DefinitionsPath)
    if (-not (Test-Path -LiteralPath $desiredRoot -PathType Container)) {
        throw "FPAC desired-state folder was not found: $desiredRoot"
    }

    $planFolder = Join-Path ([System.IO.Path]::GetFullPath($OutputPath)) "plans-$($target.Name)"
    $planFile = Join-Path $planFolder 'policy-plan.json'
    $schemaPath = Join-Path $repositoryRoot 'schemas\deployment-plan.schema.json'
    if (-not (Test-Path -LiteralPath $schemaPath -PathType Leaf)) {
        throw "FPAC deployment plan schema was not found: $schemaPath"
    }
    $schemaReference = Get-FpacSchemaReference -ArtifactDirectory $planFolder -SchemaPath $schemaPath
    if (Test-Path -LiteralPath $planFile -PathType Leaf) {
        Remove-Item -LiteralPath $planFile -Force
    }

    $headers = Get-FabricAuthenticationHeaders -TenantId $target.TenantId
    $premiumPerUserCapacityCount = 0
    $capacityMap = Get-FpacCapacityMap -Headers $headers `
        -PremiumPerUserCapacityCount ([ref] $premiumPerUserCapacityCount)
    $target = Resolve-FpacEnvironmentCapacityScopes -Target $target -CapacityMap $capacityMap

    Write-FpacModernHeader -Title 'Fabric Policy as Code (FPAC)' -Subtitle 'Building Deployment Plans' -HeaderColor Magenta -SubtitleColor Magenta
    Write-FpacModernSection -Title 'Environment Configuration'
    Write-FpacModernStatus -Message "FPAC Environment: $($target.Name)" -Status info
    Write-FpacModernStatus -Message "Definitions Root: $desiredRoot" -Status info
    Write-FpacModernStatus -Message "Tenant ID: $($target.TenantId)" -Status info
    Write-FpacModernStatus -Message "Scope: $($target.ScopeType)" -Status info
    if ($target.ScopeType -eq 'Tenant') {
        Write-FpacModernStatus -Message "Include capacities: $($target.Scopes[0].IncludeCapacities)" -Status info
    }
    if ($target.ScopeType -eq 'Capacity') {
        foreach ($capacityId in @($target.CapacityIds)) {
            Write-FpacModernStatus -Message "Capacity ID: $capacityId" -Status info
        }
    }

    $capacityCount = $capacityMap.Count - $premiumPerUserCapacityCount
    Write-FpacModernStatus -Message "Resolved $capacityCount capacity name(s) (excluding Premium Per User)" -Status success
    $temporaryRoot = Join-Path ([System.IO.Path]::GetTempPath()) "fpac-plan-$([Guid]::NewGuid().ToString('N'))"
    try {
        Write-FpacModernSection -Title 'Retrieving Policy Resources'
        $currentExport = Invoke-FabricPolicyExport -Headers $headers -Destination $temporaryRoot `
            -Target $target -CapacityMap $capacityMap -ActivityVerb Retrieving
        if (-not $currentExport.IsComplete) {
            throw "Unable to build a deployment plan because live-state discovery had $($currentExport.FailureCount) failure(s)."
        }
        Write-FpacModernStatus -Message "Discovered $($currentExport.PolicyCount) policy definition(s) in $($currentExport.ExportedCount) Policy Set(s)" -Status success
        Write-FpacModernStatus -Message "Resolved $($currentExport.WorkspaceMap.Count) workspace name(s)" -Status success

        $workspaceDetails = Get-FabricPropertyValue -InputObject $currentExport -Name 'WorkspaceDetails'
        $pacOwnerId = [string] (Get-FabricPropertyValue -InputObject $settings -Name 'PacOwnerId')
        if ([string]::IsNullOrWhiteSpace($pacOwnerId)) {
            $pacOwnerId = "fpac:$($target.Name)"
        }
        $desiredStateStrategy = [string] (Get-FabricPropertyValue -InputObject $settings -Name 'DesiredStateStrategy')
        if ([string]::IsNullOrWhiteSpace($desiredStateStrategy)) {
            $desiredStateStrategy = 'OwnedOnly'
        }
        $plan = New-FpacDeploymentPlan -DesiredRoot $desiredRoot -DeployedRoot $temporaryRoot `
            -Target $target -SchemaReference $schemaReference -CapacityMap $capacityMap `
            -WorkspaceMap $currentExport.WorkspaceMap `
            -WorkspaceDetails $workspaceDetails `
            -PacOwnerId $pacOwnerId `
            -DesiredStateStrategy $desiredStateStrategy `
            -Environments $settings.Environments `
            -DetailedOutput:$DetailedOutput

        Write-FpacModernHeader -Title 'FPAC Deployment Plan Summary' -Subtitle 'Fabric Policy as Code Resource Analysis' -HeaderColor Magenta -SubtitleColor Magenta
        Write-FpacModernCountSummary -Type 'Policy Sets' `
            -Unchanged $plan.policySets.numberUnchanged `
            -TotalChanges $plan.policySets.numberOfChanges `
            -Changes @{
                new = $plan.policySets.new.Count
                update = $plan.policySets.update.Count
                replace = $plan.policySets.replace.Count
                adopt = $plan.policySets.adopt.Count
                delete = $plan.policySets.delete.Count
            }
        Write-FpacPlanChangeDetails -ResourceType 'Policy Sets' `
            -ResourcePlan $plan.policySets -DetailedOutput:$DetailedOutput -CapacityMap $capacityMap
        $activationChanges = @($plan.activationChanges | Where-Object { [string] $_.action -ne 'Maintain' })
        if ($activationChanges.Count -gt 0) {
            Write-FpacModernSection -Title 'Activation Changes'
            foreach ($activation in $activationChanges) {
                $scopeLabel = Format-FpacScopeDisplayName -ScopeKey $activation.scopeKey -CapacityMap $capacityMap
                if ([string] $activation.action -eq 'Deactivate') {
                    Write-FpacModernStatus -Message "Deactivating $($activation.desired.workspace)/$($activation.desired.displayName) on $scopeLabel" -Status error
                    continue
                }
                if ($null -ne $activation.expectedCurrent) {
                    Write-FpacModernStatus -Message "Deactivating $($activation.expectedCurrent.workspace)/$($activation.expectedCurrent.displayName) on $scopeLabel" -Status error
                }
                Write-FpacModernStatus -Message "Activating $($activation.desired.workspace)/$($activation.desired.displayName) on $scopeLabel" -Status success
            }
        }
        else {
            Write-FpacModernStatus -Message 'No activation changes' -Status info
        }

        Write-FpacModernSection -Title 'Deployment Plan Output' -Color Green
        $policyStage = Write-FpacDeploymentPlan -Plan $plan -Path $planFile
        if ($policyStage -eq 'yes') {
            Write-FpacModernStatus -Message "Policy deployment plan created: $planFile" -Status success
        }
        else {
            Write-FpacModernStatus -Message 'Policy deployment stage skipped - no changes detected' -Status skip
        }

        switch ($DevOpsType) {
            'ado' {
                Write-Host "##vso[task.setvariable variable=deployPolicyChanges;isOutput=true]$policyStage"
            }
            'gitlab' {
                Add-Content -LiteralPath (Join-Path $repositoryRoot 'build.env') -Value "deployPolicyChanges=$policyStage"
            }
        }

        $timer.Stop()
        Write-FpacModernHeader -Title 'FPAC Build Complete' -Subtitle 'Deployment plans generated successfully' -HeaderColor Green -SubtitleColor DarkGreen
        Write-FpacModernStatus -Message "Execution time: $($timer.Elapsed.ToString('mm\:ss\.fff'))" -Status success
        return [pscustomobject]@{
            Plan            = $plan
            PlanFile        = if ($policyStage -eq 'yes') { $planFile } else { $null }
            PolicyStage     = $policyStage
            InformationLog = $Global:fpacInfoStream.ToArray()
        }
    }
    finally {
        if (Test-Path -LiteralPath $temporaryRoot) {
            Remove-Item -LiteralPath $temporaryRoot -Recurse -Force
        }
    }
}
