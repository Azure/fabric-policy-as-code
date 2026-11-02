function New-FpacPolicyPlan {
    <#
    .SYNOPSIS
    Builds a deployment plan by comparing desired state with visible Fabric state.
    .DESCRIPTION
    Returns Plan, PlanFile, PolicyStage (yes/no), and InformationLog. PlanFile is
    null when no changes exist. Does not mutate Fabric.
    .EXAMPLE
    $result = New-FpacPolicyPlan -EnvironmentName Development -DetailedOutput
    #>
    [CmdletBinding()]
    param (
        [string] $DefinitionsPath = (Join-Path (Get-Location).Path 'Definitions'),
        [string] $OutputPath = (Join-Path (Get-Location).Path 'Output'),
        [string] $GlobalSettingsPath = (Join-Path (Get-Location).Path 'Definitions\global-settings.jsonc'),
        [string] $EnvironmentName,
        [switch] $DetailedOutput,
        [ValidateSet('none', 'ado', 'gitlab')]
        [string] $DevOpsType = 'none',
        [ValidateRange(1, 10)]
        [int] $MaxRetryAttempts = 5
    )

    $ErrorActionPreference = 'Stop'
    Invoke-FpacBuildDeploymentPlansOperation -DefinitionsPath $DefinitionsPath -OutputPath $OutputPath `
        -GlobalSettingsPath $GlobalSettingsPath -EnvironmentName $EnvironmentName `
        -DetailedOutput:$DetailedOutput -DevOpsType $DevOpsType -MaxRetryAttempts $MaxRetryAttempts
}
