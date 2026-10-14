[CmdletBinding()]
param (
    [Parameter()]
    [string] $OutputPath = (Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) 'Output'),

    [Parameter()]
    [string] $GlobalSettingsPath = (Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) 'Definitions\global-settings.jsonc'),

    [Parameter()]
    [string] $EnvironmentName,

    [Parameter()]
    [ValidateRange(1, 10)]
    [int] $MaxRetryAttempts = 5
)

# Examples:
#   .\scripts\operations\Export-PolicyToFPAC.ps1
#   .\scripts\operations\Export-PolicyToFPAC.ps1 -EnvironmentName 'FabricTestGSlack' -OutputPath '.\Output'

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script:FabricApiBaseUri = 'https://api.fabric.microsoft.com/v1'
$script:MaxRetryAttempts = $MaxRetryAttempts
$helperRoot = Join-Path (Split-Path -Parent $PSScriptRoot) 'helpers'
foreach ($helperFile in Get-ChildItem -LiteralPath $helperRoot -Filter '*.ps1' -File) {
    . $helperFile.FullName
}

if ($MyInvocation.InvocationName -ne '.') {
    try {
        Invoke-FpacPolicyExportOperation -OutputPath $OutputPath `
            -GlobalSettingsPath $GlobalSettingsPath `
            -EnvironmentName $EnvironmentName `
            -MaxRetryAttempts $MaxRetryAttempts
    }
    catch {
        Write-Error $_
        exit 1
    }
}
