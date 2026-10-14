[CmdletBinding()]
param (
    [Parameter()]
    [string] $DefinitionsPath = (Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) 'Definitions'),

    [Parameter()]
    [string] $OutputPath = (Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) 'Output'),

    [Parameter()]
    [string] $GlobalSettingsPath = (Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) 'Definitions\global-settings.jsonc'),

    [Parameter()]
    [string] $EnvironmentName,

    [Parameter()]
    [switch] $DetailedOutput,

    [Parameter()]
    [ValidateSet('none', 'ado', 'gitlab')]
    [string] $DevOpsType = 'none',

    [Parameter()]
    [ValidateRange(1, 10)]
    [int] $MaxRetryAttempts = 5
)

# Examples:
#   .\scripts\Deploy\Build-DeploymentPlans.ps1 -EnvironmentName 'FabricTestGSlack'
#   .\scripts\Deploy\Build-DeploymentPlans.ps1 -EnvironmentName 'FabricTestGSlack' -DetailedOutput

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
        Invoke-FpacBuildDeploymentPlansOperation -DefinitionsPath $DefinitionsPath `
            -OutputPath $OutputPath `
            -GlobalSettingsPath $GlobalSettingsPath `
            -EnvironmentName $EnvironmentName `
            -DetailedOutput:$DetailedOutput `
            -DevOpsType $DevOpsType `
            -MaxRetryAttempts $MaxRetryAttempts | Out-Null
    }
    catch {
        Write-Error $_
        exit 1
    }
}
