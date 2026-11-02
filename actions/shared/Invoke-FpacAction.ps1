function Invoke-FpacGitHubAction {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [ValidateSet('Plan', 'Deploy')]
        [string] $Operation,
        [Parameter(Mandatory)]
        [ValidatePattern('^\d+\.\d+\.\d+$')]
        [string] $ModuleVersion,
        [Parameter(Mandatory)]
        [guid] $TenantId,
        [Parameter(Mandatory)]
        [guid] $ClientId,
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $EnvironmentName,
        [string] $DefinitionsPath = 'Definitions',
        [string] $OutputPath = 'Output',
        [string] $GlobalSettingsPath = 'Definitions\global-settings.jsonc',
        [string] $PlanFile,
        [string] $PlanSha256,
        [switch] $DetailedOutput,
        [switch] $AllowActivationReplacement,
        [switch] $AdoptUnowned,
        [switch] $WhatIfDeployment
    )

    $ErrorActionPreference = 'Stop'
    if (-not (Test-Path -LiteralPath $GlobalSettingsPath -PathType Leaf)) {
        throw "Global settings file was not found: $GlobalSettingsPath"
    }
    if ([string]::IsNullOrWhiteSpace($env:GITHUB_OUTPUT)) {
        throw 'GITHUB_OUTPUT is unavailable. Run this action in GitHub Actions.'
    }
    if ($Operation -eq 'Deploy') {
        if ($PlanSha256 -notmatch '^[a-fA-F0-9]{64}$') {
            throw 'Deployment requires the SHA-256 output of the reviewed planning job.'
        }
        if ([string]::IsNullOrWhiteSpace($PlanFile) -or -not (Test-Path -LiteralPath $PlanFile -PathType Leaf)) {
            throw "Reviewed plan file was not found: $PlanFile"
        }
        if ((Get-FileHash -LiteralPath $PlanFile -Algorithm SHA256).Hash -ne $PlanSha256) {
            throw 'Plan SHA-256 does not match the reviewed planning job. Rebuild and review the plan.'
        }
    }
    if ([string]::IsNullOrWhiteSpace($env:ACTIONS_ID_TOKEN_REQUEST_URL) -or
        [string]::IsNullOrWhiteSpace($env:ACTIONS_ID_TOKEN_REQUEST_TOKEN)) {
        throw 'GitHub OIDC is unavailable. Set permissions: id-token: write on the calling job.'
    }

    if (-not (Get-Module -ListAvailable -Name FabricPolicyAsCode | Where-Object Version -EQ ([version] $ModuleVersion))) {
        Install-Module FabricPolicyAsCode -RequiredVersion $ModuleVersion -Repository PSGallery `
            -Scope CurrentUser -Force -AllowClobber -ErrorAction Stop
    }
    Import-Module FabricPolicyAsCode -RequiredVersion $ModuleVersion -Force -ErrorAction Stop
    Disable-AzContextAutosave -Scope Process | Out-Null
    Clear-AzContext -Scope Process -Force
    $connected = $false
    try {
        $separator = if ($env:ACTIONS_ID_TOKEN_REQUEST_URL.Contains('?')) { '&' } else { '?' }
        $tokenResponse = Invoke-RestMethod -Method Get `
            -Uri "$($env:ACTIONS_ID_TOKEN_REQUEST_URL)${separator}audience=api%3A%2F%2FAzureADTokenExchange" `
            -Headers @{ Authorization = "Bearer $env:ACTIONS_ID_TOKEN_REQUEST_TOKEN" }
        if ([string]::IsNullOrWhiteSpace([string] $tokenResponse.value)) {
            throw 'GitHub did not return an OIDC token.'
        }
        Write-Host "::add-mask::$($tokenResponse.value)"
        Connect-AzAccount -ServicePrincipal -Tenant $TenantId.ToString() -ApplicationId $ClientId.ToString() `
            -FederatedToken $tokenResponse.value -SkipContextPopulation -ErrorAction Stop | Out-Null
        $connected = $true
        if ($Operation -eq 'Plan') {
            $result = New-FpacPolicyPlan -DefinitionsPath $DefinitionsPath -OutputPath $OutputPath `
                -GlobalSettingsPath $GlobalSettingsPath -EnvironmentName $EnvironmentName -DetailedOutput:$DetailedOutput
            $hasChanges = $result.PolicyStage -eq 'yes'
            $path = if ($hasChanges) { $result.PlanFile } else { '' }
            $hash = if ($hasChanges) { (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant() } else { '' }
            if ($path -match '[\r\n]') {
                throw 'Plan output path must not contain newline characters.'
            }
            @(
                "has-changes=$($hasChanges.ToString().ToLowerInvariant())"
                "plan-file=$path"
                "plan-sha256=$hash"
            ) | Add-Content -LiteralPath $env:GITHUB_OUTPUT -Encoding utf8
            if (-not [string]::IsNullOrWhiteSpace($env:GITHUB_STEP_SUMMARY)) {
                @(
                    '## FPAC plan'
                    ''
                    "Changes: $($result.Plan.numberOfChanges)"
                    ''
                    "Plan SHA-256: ``$hash``"
                    ''
                    'Review the plan artifact and planning log before approving deployment.'
                ) | Add-Content -LiteralPath $env:GITHUB_STEP_SUMMARY -Encoding utf8
            }
        }
        else {
            Invoke-FpacPolicyDeployment -PlanFile $PlanFile -GlobalSettingsPath $GlobalSettingsPath `
                -EnvironmentName $EnvironmentName -AllowActivationReplacement:$AllowActivationReplacement `
                -AdoptUnowned:$AdoptUnowned -WhatIf:$WhatIfDeployment -Confirm:$false
        }
    }
    finally {
        if ($connected) {
            Disconnect-AzAccount -Scope Process -ErrorAction Stop | Out-Null
        }
        Clear-AzContext -Scope Process -Force
    }
}

if ($MyInvocation.InvocationName -ne '.') {
    Set-StrictMode -Version Latest
    Invoke-FpacGitHubAction -Operation $env:FPAC_OPERATION -ModuleVersion $env:FPAC_MODULE_VERSION `
        -TenantId $env:FPAC_TENANT_ID -ClientId $env:FPAC_CLIENT_ID -EnvironmentName $env:FPAC_ENVIRONMENT `
        -DefinitionsPath $env:FPAC_DEFINITIONS_PATH -OutputPath $env:FPAC_OUTPUT_PATH `
        -GlobalSettingsPath $env:FPAC_GLOBAL_SETTINGS_PATH -PlanFile $env:FPAC_PLAN_FILE `
        -PlanSha256 $env:FPAC_PLAN_SHA256 -DetailedOutput:([bool]::Parse($env:FPAC_DETAILED_OUTPUT)) `
        -AllowActivationReplacement:([bool]::Parse($env:FPAC_ALLOW_ACTIVATION_REPLACEMENT)) `
        -AdoptUnowned:([bool]::Parse($env:FPAC_ADOPT_UNOWNED)) `
        -WhatIfDeployment:([bool]::Parse($env:FPAC_WHAT_IF))
}
