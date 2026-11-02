BeforeAll {
    $script:sourceManifest = Import-PowerShellDataFile (Join-Path $PSScriptRoot '..\Module\FabricPolicyAsCode\FabricPolicyAsCode.psd1')
    $script:package = & (Join-Path $PSScriptRoot '..\Module\build.ps1') -OutputPath (Join-Path $TestDrive 'package')
    Import-Module (Join-Path $script:package 'FabricPolicyAsCode.psd1') -Force
}

AfterAll {
    Remove-Module FabricPolicyAsCode -ErrorAction SilentlyContinue
}

Describe 'Consumable module package' {
    It 'validates the manifest and exports only supported commands' {
        $manifest = Test-ModuleManifest (Join-Path $script:package 'FabricPolicyAsCode.psd1')
        $manifest.Version.ToString() | Should -Be $script:sourceManifest.ModuleVersion
        @(Get-Command -Module FabricPolicyAsCode).Count | Should -Be 3
        (Get-Command -Module FabricPolicyAsCode).Name | Should -Contain 'Export-FpacPolicy'
        (Get-Command -Module FabricPolicyAsCode).Name | Should -Contain 'New-FpacPolicyPlan'
        (Get-Command -Module FabricPolicyAsCode).Name | Should -Contain 'Invoke-FpacPolicyDeployment'
    }

    It 'contains schemas and shared helpers without operator data' {
        Test-Path (Join-Path $script:package 'schemas\deployment-plan.schema.json') | Should -BeTrue
        Test-Path (Join-Path $script:package 'scripts\helpers\Invoke-FabricPolicyExport.ps1') | Should -BeTrue
        foreach ($name in @('Definitions', 'Definitionsold', 'Output', 'tests', '.git')) {
            Test-Path (Join-Path $script:package $name) | Should -BeFalse
        }
    }

    It 'does not overwrite an existing staged version' {
        { & (Join-Path $PSScriptRoot '..\Module\build.ps1') -OutputPath (Join-Path $TestDrive 'package') } |
            Should -Throw '*already exists*'
    }

    It 'forwards export options to the shared operation' {
        InModuleScope FabricPolicyAsCode {
            Mock Invoke-FpacPolicyExportOperation {}
            Export-FpacPolicy -EnvironmentName Test -OutputPath 'exports' -GlobalSettingsPath 'settings.jsonc' -MaxRetryAttempts 2
            Should -Invoke Invoke-FpacPolicyExportOperation -Times 1 -Exactly -ParameterFilter {
                $EnvironmentName -eq 'Test' -and $OutputPath -eq 'exports' -and
                $GlobalSettingsPath -eq 'settings.jsonc' -and $MaxRetryAttempts -eq 2
            }
        }

    }

    It 'returns the shared planning contract and defaults to caller paths' {
        InModuleScope FabricPolicyAsCode {
            Mock Invoke-FpacBuildDeploymentPlansOperation {
                [pscustomobject]@{ PolicyStage = 'no'; PlanFile = $null; Plan = @{ numberOfChanges = 0 } }
            }
            $result = New-FpacPolicyPlan -EnvironmentName Test -DetailedOutput
            $result.PolicyStage | Should -Be 'no'
            $result.PlanFile | Should -BeNullOrEmpty
            Should -Invoke Invoke-FpacBuildDeploymentPlansOperation -Times 1 -ParameterFilter {
                $DefinitionsPath -eq (Join-Path (Get-Location).Path 'Definitions') -and $DetailedOutput
            }
        }

    }

    It 'finds staged plan schemas before authentication without the repository' {
        InModuleScope FabricPolicyAsCode {
            Mock Get-FpacGlobalSettings { @{ Environments = @(@{ Name = 'Test' }) } }
            Mock Select-FpacEnvironment { @{ Name = 'Test'; TenantId = '11111111-1111-1111-1111-111111111111' } }
            Mock Get-FabricAuthenticationHeaders { throw 'Authentication checkpoint reached' }
            { New-FpacPolicyPlan -EnvironmentName Test -DefinitionsPath $TestDrive -OutputPath $TestDrive } |
                Should -Throw '*Authentication checkpoint reached*'
            Should -Invoke Get-FabricAuthenticationHeaders -Times 1
        }

    }

    It 'forwards WhatIf and explicit deployment safeguards' {
        InModuleScope FabricPolicyAsCode {
            Mock Invoke-FpacDeployPolicyOperation {}
            Invoke-FpacPolicyDeployment -PlanFile 'reviewed.json' -EnvironmentName Test `
                -AllowActivationReplacement -AdoptUnowned -WhatIf -Confirm:$false
            Should -Invoke Invoke-FpacDeployPolicyOperation -Times 1 -ParameterFilter {
                $PlanFile -eq 'reviewed.json' -and $AllowActivationReplacement -and $AdoptUnowned -and
                $WhatIf -and (Test-Path -LiteralPath $SchemaPath)
            }
        }

    }

    It 'resolves a plan by environment and refuses an ambiguous default' {
        InModuleScope FabricPolicyAsCode {
            Mock Invoke-FpacDeployPolicyOperation {}
            { Invoke-FpacPolicyDeployment -Confirm:$false } | Should -Throw '*Specify EnvironmentName*'
            Invoke-FpacPolicyDeployment -EnvironmentName Test -OutputPath 'output' -Confirm:$false
            Should -Invoke Invoke-FpacDeployPolicyOperation -Times 1 -ParameterFilter {
                $PlanFile -eq (Join-Path 'output' 'plans-Test\policy-plan.json')
            }
        }

    }

    It 'fails unattended authentication instead of prompting' {
        InModuleScope FabricPolicyAsCode {
            Mock Get-AzContext { $null }
            Mock Test-FpacCICDEnvironment { $true }
            Mock Connect-AzAccount {}
            { Get-FabricAuthenticationHeaders -TenantId '11111111-1111-1111-1111-111111111111' } |
                Should -Throw '*Authenticate noninteractively*'
            Should -Invoke Connect-AzAccount -Times 0
        }
    }
}
