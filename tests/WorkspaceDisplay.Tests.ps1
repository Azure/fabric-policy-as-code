BeforeAll {
    . (Join-Path $PSScriptRoot '..\scripts\Deploy\Build-DeploymentPlans.ps1')
}

Describe 'Workspace names in plan details' {
    BeforeEach {
        Mock Write-FpacModernSection {}
        Mock Write-FpacModernStatus {}
        Mock Write-FpacColoredOutput {}
        $script:firstId = '11111111-1111-1111-1111-111111111111'
        $script:secondId = '22222222-2222-2222-2222-222222222222'
        $script:workspaceMap = @{ Finance = $script:firstId; Sales = $script:secondId }
        $script:desired = [pscustomobject]@{
            properties = [pscustomobject]@{
                workspace = 'Governance'; displayName = 'Set'
                policies = @(
                    [pscustomobject]@{
                        name = 'Allowed workspaces'
                        definition = [pscustomobject]@{
                            parameters = [pscustomobject]@{
                                condition1Values = [pscustomobject]@{
                                    metadata = [pscustomobject]@{ targetProperty = 'workspace.id' }
                                    defaultValue = @($script:firstId)
                                }
                            }
                            conditions = @(
                                [pscustomobject]@{
                                    targetProperty = 'workspace.id'
                                    predicate = [pscustomobject]@{ values = @($script:firstId) }
                                }
                            )
                        }
                    }
                )
            }
        }
        $script:deployed = $script:desired | ConvertTo-Json -Depth 30 | ConvertFrom-Json
        $script:deployed.properties.policies[0].definition.parameters.condition1Values.defaultValue = @($script:secondId)
        $script:deployed.properties.policies[0].definition.conditions[0].predicate.values = @($script:secondId)
    }

    It 'resolves scalar parameter and condition differences without changing saved IDs' {
        $differences = @(Get-FpacObjectDifferences -Desired $script:desired.properties `
            -Deployed $script:deployed.properties -Path 'properties')
        $plan = New-FpacPlanBucket
        $plan.numberOfChanges = 1
        $plan.update.set = @{
            desired = $script:desired; deployed = $script:deployed
            changes = @('policies'); differences = $differences
        }
        $before = ConvertTo-FpacCanonicalJson -InputObject $plan

        Write-FpacPlanChangeDetails -ResourceType 'Policy Sets' -ResourcePlan $plan -DetailedOutput -WorkspaceMap $script:workspaceMap

        Should -Invoke Write-FpacColoredOutput -Times 2 -Exactly -ParameterFilter {
            $Message.Trim() -eq '- Sales' -and $Color -eq [ConsoleColor]::Red
        }
        Should -Invoke Write-FpacColoredOutput -Times 2 -Exactly -ParameterFilter {
            $Message.Trim() -eq '+ Finance' -and $Color -eq [ConsoleColor]::Green
        }
        Should -Invoke Write-FpacColoredOutput -Times 0 -ParameterFilter { $Message -match '11111111|22222222' }
        ConvertTo-FpacCanonicalJson -InputObject $plan | Should -Be $before
    }

    It 'resolves added policy content and new resource dumps without mutating the resource' {
        $before = ConvertTo-FpacCanonicalJson -InputObject $script:desired
        Write-FpacDetailedChanges -ResourceType 'Policy Sets' -Action New -Name 'Governance/Set' `
            -Desired $script:desired -WorkspaceMap $script:workspaceMap
        Should -Invoke Write-FpacColoredOutput -Times 2 -Exactly -ParameterFilter { $Message -like '*"Finance"*' }
        Should -Invoke Write-FpacColoredOutput -Times 0 -ParameterFilter { $Message -like "*$($script:firstId)*" }
        ConvertTo-FpacCanonicalJson -InputObject $script:desired | Should -Be $before
    }

    It 'resolves nested values in a whole-policy addition' {
        Write-FpacDetailedChanges -ResourceType 'Policy Sets' -Action Update -Name 'Governance/Set' `
            -Desired $script:desired -Deployed $script:deployed -WorkspaceMap $script:workspaceMap -Differences @(
                [pscustomobject]@{
                    path = 'properties.policies[Allowed workspaces]'; change = 'Add'
                    oldValue = $null; newValue = $script:desired.properties.policies[0]
                }
            )
        Should -Invoke Write-FpacColoredOutput -Times 1 -Exactly -ParameterFilter {
            $Message -like '*"Finance"*' -and $Message -notlike "*$($script:firstId)*"
        }
    }

    It 'preserves empty and singleton array shapes in display copies' {
        $copy = ConvertTo-FpacPlanDisplayValue -Value $script:desired.properties -WorkspaceMap $script:workspaceMap
        $parameter = $copy.policies[0].definition.parameters.condition1Values
        $parameter.defaultValue -is [array] | Should -BeTrue
        $parameter.defaultValue.Count | Should -Be 1
        $parameter.defaultValue[0] | Should -Be 'Finance'
        $script:desired.properties.policies[0].definition.parameters.condition1Values.defaultValue = @()
        $copy = ConvertTo-FpacPlanDisplayValue -Value $script:desired.properties -WorkspaceMap $script:workspaceMap
        $copy.policies[0].definition.parameters.condition1Values.defaultValue -is [array] | Should -BeTrue
        $copy.policies[0].definition.parameters.condition1Values.defaultValue.Count | Should -Be 0
    }

    It 'does not translate unrelated values just because they match a workspace ID' {
        $script:desired.properties.policies[0].definition.parameters.condition1Values.metadata.targetProperty = 'item.type'
        $copy = ConvertTo-FpacPlanDisplayValue -Value $script:desired.properties -WorkspaceMap $script:workspaceMap
        $copy.policies[0].definition.parameters.condition1Values.defaultValue[0] | Should -Be $script:firstId
        $copy.policies[0].definition.conditions[0].predicate.values[0] | Should -Be 'Finance'
    }

    It 'uses the metadata from each side of a replacement' {
        $script:desired.properties.policies[0].definition.parameters.condition1Values.metadata.targetProperty = 'item.type'
        Write-FpacDetailedChanges -ResourceType 'Policy Sets' -Action Update -Name 'Governance/Set' `
            -Desired $script:desired -Deployed $script:deployed -WorkspaceMap $script:workspaceMap -Differences @(
                [pscustomobject]@{
                    path = 'properties.policies[Allowed workspaces].definition.parameters.condition1Values.defaultValue[]'
                    change = 'Replace'; oldValue = $script:secondId; newValue = $script:firstId
                }
            )
        Should -Invoke Write-FpacColoredOutput -Times 1 -Exactly -ParameterFilter { $Message.Trim() -eq '- Sales' }
        Should -Invoke Write-FpacColoredOutput -Times 1 -Exactly -ParameterFilter { $Message.Trim() -eq "+ $($script:firstId)" }
    }

    It 'retains an unknown ID when a workspace name is unavailable' {
        ConvertTo-FpacPlanDisplayValue -Value 'unknown-id' -TargetProperty 'workspace.id' -WorkspaceMap $script:workspaceMap |
            Should -Be 'unknown-id'
    }
}
