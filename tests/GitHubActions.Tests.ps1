BeforeAll {
    Import-Module PowerShellGet
    Import-Module (Join-Path $PSScriptRoot '..\Module\FabricPolicyAsCode\FabricPolicyAsCode.psd1') -Force
    . (Join-Path $PSScriptRoot '..\actions\shared\Invoke-FpacAction.ps1')
}

AfterAll {
    Remove-Module FabricPolicyAsCode -ErrorAction SilentlyContinue
}

Describe 'FPAC composite action runner' {
    BeforeEach {
        $script:savedEnvironment = @{}
        foreach ($name in @('GITHUB_OUTPUT', 'GITHUB_STEP_SUMMARY', 'ACTIONS_ID_TOKEN_REQUEST_URL', 'ACTIONS_ID_TOKEN_REQUEST_TOKEN')) {
            $script:savedEnvironment[$name] = [Environment]::GetEnvironmentVariable($name)
        }
        $env:GITHUB_OUTPUT = Join-Path $TestDrive 'outputs.txt'
        $env:GITHUB_STEP_SUMMARY = Join-Path $TestDrive 'summary.md'
        $env:ACTIONS_ID_TOKEN_REQUEST_URL = 'https://example.invalid/oidc?request=1'
        $env:ACTIONS_ID_TOKEN_REQUEST_TOKEN = 'test-request-token'
        Set-Content -LiteralPath $env:GITHUB_OUTPUT -Value ''
        $script:settingsFile = Join-Path $TestDrive 'settings.jsonc'
        Set-Content -LiteralPath $script:settingsFile -Value '{}'
        $script:planFile = Join-Path $TestDrive 'policy-plan.json'
        Set-Content -LiteralPath $script:planFile -Value '{"numberOfChanges":1}'
        $script:parameters = @{
            ModuleVersion = '0.1.0'
            TenantId = '11111111-1111-1111-1111-111111111111'
            ClientId = '22222222-2222-2222-2222-222222222222'
            EnvironmentName = 'Production'
            GlobalSettingsPath = $script:settingsFile
        }
        Mock Get-Module { [pscustomobject]@{ Version = [version] '0.1.0' } } -ParameterFilter {
            $Name -eq 'FabricPolicyAsCode' -and $ListAvailable
        }
        Mock Install-Module {}
        Mock Import-Module {} -ParameterFilter { $Name -eq 'FabricPolicyAsCode' }
        Mock Disable-AzContextAutosave {}
        Mock Clear-AzContext {}
        Mock Connect-AzAccount {}
        Mock Disconnect-AzAccount {}
        Mock Invoke-RestMethod { @{ value = 'test-oidc-assertion' } }
        Mock New-FpacPolicyPlan {
            [pscustomobject]@{
                PolicyStage = 'yes'; PlanFile = $script:planFile; Plan = @{ numberOfChanges = 1 }
            }
        }
        Mock Invoke-FpacPolicyDeployment {}
        Mock Write-Host {}
    }

    AfterEach {
        foreach ($entry in $script:savedEnvironment.GetEnumerator()) {
            [Environment]::SetEnvironmentVariable($entry.Key, $entry.Value)
        }
    }

    It 'authenticates with federation and reports exact plan outputs' {
        Invoke-FpacGitHubAction -Operation Plan @script:parameters -DetailedOutput
        $outputs = Get-Content -LiteralPath $env:GITHUB_OUTPUT
        $outputs | Should -Contain 'has-changes=true'
        $outputs | Should -Contain "plan-file=$script:planFile"
        $hash = (Get-FileHash -LiteralPath $script:planFile).Hash.ToLowerInvariant()
        $outputs | Should -Contain "plan-sha256=$hash"
        Should -Invoke Connect-AzAccount -Times 1 -ParameterFilter {
            $ServicePrincipal -and $FederatedToken -eq 'test-oidc-assertion' -and $SkipContextPopulation
        }
        Should -Invoke Invoke-RestMethod -Times 1 -ParameterFilter {
            $Uri -eq 'https://example.invalid/oidc?request=1&audience=api%3A%2F%2FAzureADTokenExchange'
        }
        Should -Invoke Disconnect-AzAccount -Times 1
    }

    It 'reports no changes without trying to hash a missing plan' {
        Mock New-FpacPolicyPlan {
            [pscustomobject]@{ PolicyStage = 'no'; PlanFile = $null; Plan = @{ numberOfChanges = 0 } }
        }
        Invoke-FpacGitHubAction -Operation Plan @script:parameters
        Get-Content -LiteralPath $env:GITHUB_OUTPUT | Should -Contain 'has-changes=false'
        Get-Content -LiteralPath $env:GITHUB_OUTPUT | Should -Contain 'plan-file='
        Get-Content -LiteralPath $env:GITHUB_OUTPUT | Should -Contain 'plan-sha256='
        Should -Invoke Invoke-FpacPolicyDeployment -Times 0
    }

    It 'deploys the hash-verified plan without rebuilding it' {
        $hash = (Get-FileHash -LiteralPath $script:planFile).Hash
        Invoke-FpacGitHubAction -Operation Deploy @script:parameters -PlanFile $script:planFile -PlanSha256 $hash `
            -WhatIfDeployment -AllowActivationReplacement -AdoptUnowned
        Should -Invoke New-FpacPolicyPlan -Times 0
        Should -Invoke Invoke-FpacPolicyDeployment -Times 1 -ParameterFilter {
            $PlanFile -eq $script:planFile -and $WhatIf -and $AllowActivationReplacement -and $AdoptUnowned
        }
    }

    It 'rejects plan tampering before authentication' {
        $hash = (Get-FileHash -LiteralPath $script:planFile).Hash
        Add-Content -LiteralPath $script:planFile -Value 'changed'
        { Invoke-FpacGitHubAction -Operation Deploy @script:parameters -PlanFile $script:planFile -PlanSha256 $hash } |
            Should -Throw '*SHA-256 does not match*'
        Should -Invoke Connect-AzAccount -Times 0
        Should -Invoke Invoke-FpacPolicyDeployment -Times 0
    }

    It 'rejects a missing approval hash before authentication' {
        { Invoke-FpacGitHubAction -Operation Deploy @script:parameters -PlanFile $script:planFile } |
            Should -Throw '*requires the SHA-256*'
        Should -Invoke Connect-AzAccount -Times 0
    }

    It 'fails with explicit guidance when OIDC permission is missing' {
        $env:ACTIONS_ID_TOKEN_REQUEST_URL = ''
        { Invoke-FpacGitHubAction -Operation Plan @script:parameters } | Should -Throw '*id-token: write*'
        Should -Invoke Connect-AzAccount -Times 0
    }

    It 'cleans up authentication and propagates operation failure' {
        Mock New-FpacPolicyPlan { throw 'Fabric discovery failed' }
        { Invoke-FpacGitHubAction -Operation Plan @script:parameters } | Should -Throw '*Fabric discovery failed*'
        Should -Invoke Disconnect-AzAccount -Times 1
        Should -Invoke Clear-AzContext -Times 2
    }

    It 'installs only the explicitly requested Gallery version when missing' {
        Mock Get-Module { @() } -ParameterFilter { $Name -eq 'FabricPolicyAsCode' -and $ListAvailable }
        Invoke-FpacGitHubAction -Operation Plan @script:parameters
        Should -Invoke Install-Module -Times 1 -ParameterFilter {
            $Name -eq 'FabricPolicyAsCode' -and $RequiredVersion -eq '0.1.0' -and $Repository -eq 'PSGallery'
        }
    }
}
