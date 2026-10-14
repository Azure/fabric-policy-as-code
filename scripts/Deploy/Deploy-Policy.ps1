[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
param (
    [Parameter()]
    [string] $OutputPath = (Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) 'Output'),

    [Parameter()]
    [string] $GlobalSettingsPath = (Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) 'Definitions\global-settings.jsonc'),

    [Parameter()]
    [string] $EnvironmentName,

    [Parameter()]
    [string] $PlanFile,

    [Parameter()]
    [ValidateRange(1, 10)]
    [int] $MaxRetryAttempts = 5,

    [Parameter()]
    [ValidateRange(1, 7200)]
    [int] $OperationTimeoutSeconds = 1800,

    [Parameter()]
    [switch] $AllowActivationReplacement,

    [Parameter()]
    [switch] $AdoptUnowned
)

# Examples:
#   .\scripts\Deploy\Deploy-Policy.ps1 -EnvironmentName 'FabricTestGSlack' -WhatIf
#   .\scripts\Deploy\Deploy-Policy.ps1 -EnvironmentName 'FabricTestGSlack' -Confirm:$false

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repositoryRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$script:FabricApiBaseUri = 'https://api.fabric.microsoft.com/v1'
$script:MaxRetryAttempts = $MaxRetryAttempts
$helperRoot = Join-Path (Split-Path -Parent $PSScriptRoot) 'helpers'
foreach ($helperFile in Get-ChildItem -LiteralPath $helperRoot -Filter '*.ps1' -File) {
    . $helperFile.FullName
}

$schemaPath = Join-Path $repositoryRoot 'schemas\deployment-plan.schema.json'

if ($MyInvocation.InvocationName -ne '.') {
    try {
        if ([string]::IsNullOrWhiteSpace($PlanFile)) {
            if ([string]::IsNullOrWhiteSpace($EnvironmentName)) {
                throw 'Specify EnvironmentName when PlanFile is not provided.'
            }
            $PlanFile = Join-Path ([System.IO.Path]::GetFullPath($OutputPath)) "plans-$EnvironmentName\policy-plan.json"
        }
        Invoke-FpacDeployPolicyOperation -PlanFile $PlanFile `
            -GlobalSettingsPath $GlobalSettingsPath `
            -EnvironmentName $EnvironmentName `
            -SchemaPath $schemaPath `
            -MaxRetryAttempts $MaxRetryAttempts `
            -OperationTimeoutSeconds $OperationTimeoutSeconds `
            -AllowActivationReplacement:$AllowActivationReplacement `
            -AdoptUnowned:$AdoptUnowned | Out-Null
    }
    catch {
        Write-Error $_
        exit 1
    }
}
