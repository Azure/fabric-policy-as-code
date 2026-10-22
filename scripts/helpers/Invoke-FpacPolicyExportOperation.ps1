function Invoke-FpacPolicyExportOperation {
    param (
        [Parameter(Mandatory)]
        [string] $OutputPath,

        [Parameter(Mandatory)]
        [string] $GlobalSettingsPath,

        [Parameter()]
        [string] $EnvironmentName,

        [Parameter(Mandatory)]
        [ValidateRange(1, 10)]
        [int] $MaxRetryAttempts
    )

    $script:MaxRetryAttempts = $MaxRetryAttempts
    $repositoryRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $settings = Get-FpacGlobalSettings -Path $GlobalSettingsPath
    $target = Select-FpacEnvironment -Environments $settings.Environments -EnvironmentName $EnvironmentName
    $destinationPath = Resolve-FpacScopeOutputPath -OutputRoot $OutputPath -ScopeName $target.Name
    $displayPath = [System.IO.Path]::GetRelativePath($repositoryRoot, $destinationPath)
    if (-not (Confirm-FpacOutputReplacement -DestinationPath $destinationPath -DisplayPath $displayPath)) {
        Write-Host "Export cancelled. Existing output folder '$destinationPath' was not changed."
        return
    }

    $headers = Get-FabricAuthenticationHeaders -TenantId $target.TenantId
    $capacityMap = Get-FpacCapacityMap -Headers $headers
    $target = Resolve-FpacEnvironmentCapacityScopes -Target $target -CapacityMap $capacityMap
    if ($target.ScopeType -eq 'Capacity') {
        $capacityDescriptions = foreach ($scope in @($target.Scopes)) {
            "'$($scope.Name)' ($($scope.CapacityId))"
        }
        Write-Host "Connecting to FPACEnv '$($target.Name)' (capacities: $($capacityDescriptions -join ', '); tenant $($target.TenantId))..."
    }
    else {
        Write-Host "Connecting to FPACEnv '$($target.Name)' (tenant $($target.TenantId); includeCapacities: $($target.Scopes[0].IncludeCapacities))..."
    }

    Write-Host "Authentication successful. Exporting FPAC policy artifacts to '$destinationPath'."
    $exportTimer = [System.Diagnostics.Stopwatch]::StartNew()
    $result = Invoke-FabricPolicyExport -Headers $headers -Destination $destinationPath `
        -Target $target -CapacityMap $capacityMap
    $exportTimer.Stop()
    if (-not $result.IsComplete) {
        Write-Host "Export stopped with $($result.FailureCount) failure(s): $($result.ExportedCount) Policy Set(s), $($result.PolicyCount) rule(s), $($result.SkippedScopeCount) out-of-scope set(s). Elapsed: $($exportTimer.Elapsed.ToString('hh\:mm\:ss'))."
        throw "Export is incomplete: $($result.FailureCount) workspace/item failure(s). Review manifest.json."
    }

    Write-Host "Export complete: $($result.ExportedCount) Policy Set(s), $($result.PolicyCount) rule(s), $($result.SkippedScopeCount) out-of-scope set(s); scanned $($result.WorkspaceCount) workspace(s)."
    Write-Host "Elapsed: $($exportTimer.Elapsed.ToString('hh\:mm\:ss')). Output: $($result.Destination)"
}
