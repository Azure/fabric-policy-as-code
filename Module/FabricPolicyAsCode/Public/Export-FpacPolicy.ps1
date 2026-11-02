function Export-FpacPolicy {
    <#
    .SYNOPSIS
    Exports visible Fabric policy artifacts for a configured FPAC environment.
    .DESCRIPTION
    Uses the current Az.Accounts context. Writes reusable definitions, assignments,
    and an export manifest. Incomplete discovery is a terminating error.
    .EXAMPLE
    Export-FpacPolicy -EnvironmentName Development
    #>
    [CmdletBinding()]
    param (
        [string] $OutputPath = (Join-Path (Get-Location).Path 'Output'),
        [string] $GlobalSettingsPath = (Join-Path (Get-Location).Path 'Definitions\global-settings.jsonc'),
        [string] $EnvironmentName,
        [ValidateRange(1, 10)]
        [int] $MaxRetryAttempts = 5
    )

    $ErrorActionPreference = 'Stop'
    Invoke-FpacPolicyExportOperation -OutputPath $OutputPath -GlobalSettingsPath $GlobalSettingsPath `
        -EnvironmentName $EnvironmentName -MaxRetryAttempts $MaxRetryAttempts
}
