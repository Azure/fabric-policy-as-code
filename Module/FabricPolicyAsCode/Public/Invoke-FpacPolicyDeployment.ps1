function Invoke-FpacPolicyDeployment {
    <#
    .SYNOPSIS
    Deploys a previously reviewed FPAC plan.
    .DESCRIPTION
    Preserves schema, tenant, ownership, environment, stale-state, adoption, and
    activation-replacement safeguards. Supports WhatIf and Confirm.
    .EXAMPLE
    Invoke-FpacPolicyDeployment -EnvironmentName Development -WhatIf
    .EXAMPLE
    Invoke-FpacPolicyDeployment -PlanFile .\reviewed\policy-plan.json -Confirm:$false
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    param (
        [string] $OutputPath = (Join-Path (Get-Location).Path 'Output'),
        [string] $GlobalSettingsPath = (Join-Path (Get-Location).Path 'Definitions\global-settings.jsonc'),
        [string] $EnvironmentName,
        [string] $PlanFile,
        [ValidateRange(1, 10)]
        [int] $MaxRetryAttempts = 5,
        [ValidateRange(1, 7200)]
        [int] $OperationTimeoutSeconds = 1800,
        [switch] $AllowActivationReplacement,
        [switch] $AdoptUnowned
    )

    $ErrorActionPreference = 'Stop'
    if ([string]::IsNullOrWhiteSpace($PlanFile)) {
        if ([string]::IsNullOrWhiteSpace($EnvironmentName)) {
            throw 'Specify EnvironmentName when PlanFile is not provided.'
        }
        $PlanFile = Join-Path $OutputPath "plans-$EnvironmentName\policy-plan.json"
    }
    $parameters = @{
        PlanFile = $PlanFile
        GlobalSettingsPath = $GlobalSettingsPath
        EnvironmentName = $EnvironmentName
        SchemaPath = Join-Path $script:PackageRoot 'schemas\deployment-plan.schema.json'
        MaxRetryAttempts = $MaxRetryAttempts
        OperationTimeoutSeconds = $OperationTimeoutSeconds
        AllowActivationReplacement = $AllowActivationReplacement
        AdoptUnowned = $AdoptUnowned
    }
    # The operation owns the individual ShouldProcess decisions.
    foreach ($name in @('WhatIf', 'Confirm')) {
        if ($PSBoundParameters.ContainsKey($name)) {
            $parameters[$name] = $PSBoundParameters[$name]
        }
    }
    Invoke-FpacDeployPolicyOperation @parameters
}
