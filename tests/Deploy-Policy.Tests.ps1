BeforeAll {
    $scriptPath = Join-Path $PSScriptRoot '..\scripts\Deploy\Deploy-Policy.ps1'
    . $scriptPath
}

Describe 'FPAC Policy Set deployment' {
    BeforeEach {
        Mock Write-FpacModernHeader {}
        Mock Write-FpacModernSection {}
        Mock Write-FpacModernStatus {}
    }

    It 'materializes FPAC parameters into a native Fabric definition' {
        $policySet = [pscustomobject]@{
            properties = [pscustomobject]@{
                scope = [pscustomobject]@{
                    type = 'Capacity'
                    id = '22222222-2222-2222-2222-222222222222'
                }
                policies = @(
                    [pscustomobject]@{
                        name = 'policy-one'
                        definition = [pscustomobject]@{
                            displayName = 'Policy One'
                            description = 'Description'
                            parameters = [pscustomobject]@{
                                condition1Values = [pscustomobject]@{
                                    type = 'Array'
                                    defaultValue = @('Lakehouse', 'Notebook')
                                }
                            }
                            policy = 'ItemCreation'
                            conditions = @(
                                [pscustomobject]@{
                                    type = 'Dynamic'
                                    targetProperty = 'item.type'
                                    predicate = [pscustomobject]@{
                                        operator = 'AnyOf'
                                        values = @("[parameters('condition1Values')]")
                                    }
                                }
                            )
                            effects = @([pscustomobject]@{ type = 'Allow' })
                        }
                    }
                )
            }
        }

        $definition = New-FabricPolicySetDefinition -PolicySet $policySet
        $content = [Text.Encoding]::UTF8.GetString(
            [Convert]::FromBase64String($definition.parts[0].payload)
        ) | ConvertFrom-Json -Depth 100

        $definition.format | Should -Be 'Beta'
        $content.policyRules.Count | Should -Be 1
        $content.policyRules[0].conditions[0].predicate.values.Count | Should -Be 2
        $content.policyRules[0].conditions[0].predicate.values[0] | Should -Be 'Lakehouse'
        $content.policyRules[0].conditions[0].predicate.values[1] | Should -Be 'Notebook'
        $null -eq $content.policyRules[0].PSObject.Properties['parameters'] | Should -Be $true
        $content.properties.scope.type | Should -Be 'Capacity'
        $null -eq $content.properties.scope.PSObject.Properties['id'] | Should -Be $true
    }

    It 'uses the capacity activation endpoint and payload' {
        Mock Invoke-FabricApiRequest {
            [pscustomobject]@{ StatusCode = 200; Headers = @{}; Body = $null }
        }

        Set-FabricPolicySetStatus -WorkspaceId 'workspace-id' -PolicySetId 'set-id' `
            -Scope ([pscustomobject]@{ type = 'Capacity'; id = 'capacity-id' }) `
            -DesiredStatus Active -CurrentStatus Inactive -Headers @{} -AllowReplace

        Assert-MockCalled Invoke-FabricApiRequest -Times 1 -ParameterFilter {
            $Method -eq 'POST' -and
            $Uri -eq 'https://api.fabric.microsoft.com/v1/workspaces/workspace-id/policySets/set-id/activate?allowReplace=true' -and
            $Body.scopeType -eq 'Capacity' -and
            $Body.capacityId -eq 'capacity-id'
        }
    }

    It 'uses the tenant admin deactivation endpoint' {
        Mock Invoke-FabricApiRequest {
            [pscustomobject]@{ StatusCode = 200; Headers = @{}; Body = $null }
        }

        Set-FabricPolicySetStatus -WorkspaceId 'workspace-id' -PolicySetId 'set-id' `
            -Scope ([pscustomobject]@{ type = 'Tenant' }) `
            -DesiredStatus Inactive -CurrentStatus Active -Headers @{}

        Assert-MockCalled Invoke-FabricApiRequest -Times 1 -ParameterFilter {
            $Method -eq 'POST' -and
            $Uri -eq 'https://api.fabric.microsoft.com/v1/admin/workspaces/workspace-id/policySets/set-id/deactivate'
        }
    }

    It 'round trips ownership markers without changing the human description' {
        $description = Format-FpacOwnershipDescription -Description 'Human text' `
            -PacOwnerId 'owner-one' -FpacId 'policy-one' -MaxLength 256
        $metadata = Get-FpacOwnershipMetadata -Description $description

        $metadata.PacOwnerId | Should -Be 'owner-one'
        $metadata.FpacId | Should -Be 'policy-one'
        (Get-FpacHumanDescription -Description $description) | Should -Be 'Human text'
    }

    It 'stops when the active Policy Set changed after plan generation' {
        $changes = @(
            [pscustomobject]@{
                scopeKey = 'Capacity:capacity-id'
                action = 'Replace'
                desired = [pscustomobject]@{ workspace = 'Workspace'; displayName = 'Desired' }
                expectedCurrent = [pscustomobject]@{ workspace = 'Workspace'; displayName = 'Expected' }
            }
        )
        $policySets = [System.Collections.Hashtable]::new([System.StringComparer]::OrdinalIgnoreCase)
        $policySets['Actual'] = [pscustomobject]@{
            DisplayName = 'Actual'
            Status = 'Active'
            Scope = [pscustomobject]@{ type = 'Capacity'; id = 'capacity-id' }
        }
        $inventory = [System.Collections.Hashtable]::new([System.StringComparer]::OrdinalIgnoreCase)
        $inventory['Workspace'] = [pscustomobject]@{
            Name = 'Workspace'
            PolicySets = $policySets
        }

        $threw = $false
        try {
            Assert-FpacActivationChangesCurrent -ActivationChanges $changes -Inventory $inventory
        }
        catch {
            $threw = $_.Exception.Message -like '*Rebuild the plan.'
        }
        $threw | Should -Be $true
    }

    It 'updates owned rules individually and removes obsolete owned rules' {
        $policySet = [pscustomobject]@{
            properties = [pscustomobject]@{
                scope = [pscustomobject]@{ type = 'Capacity'; id = 'capacity-id' }
                policies = @(
                    [pscustomobject]@{
                        name = 'item-rule'
                        metadata = [pscustomobject]@{
                            pacOwnerId = 'fpac'
                            fpacId = 'item-rule'
                        }
                        definition = [pscustomobject]@{
                            displayName = 'Item Rule'
                            parameters = [pscustomobject]@{}
                            policy = 'ItemCreation'
                            conditions = @([pscustomobject]@{ type = 'Static' })
                            effects = @([pscustomobject]@{ type = 'Allow' })
                        }
                    }
                )
            }
        }
        Mock Get-FabricPolicyRules {
            @(
                [pscustomobject]@{
                    id = 'old-item-rule'
                    displayName = 'Old Item Rule'
                    description = '[[FPAC:v1;owner=fpac;id=item-rule]]'
                    policy = 'ItemCreation'
                    conditions = @([pscustomobject]@{ type = 'Static' })
                    effects = @([pscustomobject]@{ type = 'Allow' })
                },
                [pscustomobject]@{
                    id = 'obsolete-rule'
                    displayName = 'Obsolete Rule'
                    description = '[[FPAC:v1;owner=fpac;id=obsolete-rule]]'
                    policy = 'ExternalDataSharing'
                    conditions = @([pscustomobject]@{ type = 'Static' })
                    effects = @([pscustomobject]@{ type = 'Allow' })
                }
            )
        }
        Mock Invoke-FabricApiRequest {
            [pscustomobject]@{ StatusCode = 200; Headers = @{}; Body = $null }
        }

        Set-FabricPolicySetRules -PolicySet $policySet -WorkspaceId 'workspace-id' `
            -PolicySetId 'set-id' -Headers @{} -PacOwnerId 'fpac'

        Assert-MockCalled Invoke-FabricApiRequest -Times 1 -ParameterFilter {
            $Method -eq 'PATCH' -and
            $Uri -eq 'https://api.fabric.microsoft.com/v1/workspaces/workspace-id/policySets/set-id/policyRules/old-item-rule?beta=true' -and
            $Body.displayName -eq 'Item Rule'
        }
        Assert-MockCalled Invoke-FabricApiRequest -Times 1 -ParameterFilter {
            $Method -eq 'DELETE' -and
            $Uri -eq 'https://api.fabric.microsoft.com/v1/workspaces/workspace-id/policySets/set-id/policyRules/obsolete-rule?beta=true'
        }
    }

    It 'applies new update replace and delete actions from a validated plan' {
        $settingsPath = Join-Path $TestDrive 'global-settings.jsonc'
        @'
{
  "pacOwnerId": "fpac:Test",
  "desiredStateStrategy": "OwnedOnly",
  "environments": [
    {
      "name": "Test",
      "tenantId": "11111111-1111-1111-1111-111111111111",
      "scope": [
        { "name": "TestCapacity" }
      ]
    }
  ]
}
'@ | Set-Content -LiteralPath $settingsPath -Encoding utf8

        $scope = [ordered]@{
            type = 'Capacity'
            id = '22222222-2222-2222-2222-222222222222'
        }
        function New-TestPolicySet([string] $displayName) {
            return [ordered]@{
                name = $displayName.ToLowerInvariant()
                properties = [ordered]@{
                    displayName = $displayName
                    workspace = 'Workspace'
                    scope = $scope
                    status = 'Inactive'
                    policies = @()
                }
            }
        }
        $newSet = New-TestPolicySet 'New Set'
        $updateDesired = New-TestPolicySet 'Updated Set'
        $updateDeployed = New-TestPolicySet 'Update Set'
        $replaceDesired = New-TestPolicySet 'Replacement Set'
        $replaceDeployed = New-TestPolicySet 'Replace Set'
        $deleteSet = New-TestPolicySet 'Delete Set'
        $plan = [ordered]@{
            '$schema' = '../../schemas/deployment-plan.schema.json'
            createdOn = '2026-10-13 12:00:00Z'
            pacOwnerId = 'fpac:Test'
            desiredStateStrategy = 'OwnedOnly'
            environment = [ordered]@{
                name = 'Test'
                tenantId = '11111111-1111-1111-1111-111111111111'
                scopes = @(
                    [ordered]@{
                        type = 'Capacity'
                        capacityId = '22222222-2222-2222-2222-222222222222'
                    }
                )
            }
            policySets = [ordered]@{
                new = [ordered]@{ new = $newSet }
                update = [ordered]@{
                    update = [ordered]@{
                        name = 'update'
                        changes = @('displayName')
                        differences = @()
                        desired = $updateDesired
                        deployed = $updateDeployed
                    }
                }
                replace = [ordered]@{
                    replace = [ordered]@{
                        name = 'replace'
                        changes = @('scope')
                        differences = @()
                        desired = $replaceDesired
                        deployed = $replaceDeployed
                    }
                }
                adopt = [ordered]@{}
                delete = [ordered]@{ delete = $deleteSet }
                numberOfChanges = 4
                numberUnchanged = 0
            }
            activationChanges = @()
            numberOfChanges = 4
            numberUnchanged = 0
        }
        $planPath = Join-Path $TestDrive 'policy-plan.json'
        $plan | ConvertTo-Json -Depth 100 | Set-Content -LiteralPath $planPath -Encoding utf8

        $policySets = [System.Collections.Hashtable]::new([System.StringComparer]::OrdinalIgnoreCase)
        foreach ($entry in @(
            @{ Name = 'Update Set'; Id = 'update-id' },
            @{ Name = 'Replace Set'; Id = 'replace-id' },
            @{ Name = 'Delete Set'; Id = 'delete-id' }
        )) {
            $policySets[$entry.Name] = [pscustomobject]@{
                id = $entry.Id
                displayName = $entry.Name
                type = 'PolicySet'
            }
        }
        $inventory = [System.Collections.Hashtable]::new([System.StringComparer]::OrdinalIgnoreCase)
        $inventory['Workspace'] = [pscustomobject]@{
            Id = 'workspace-id'
            Name = 'Workspace'
            PolicySets = $policySets
        }

        Mock Get-FabricAuthenticationHeaders { @{} }
        Mock Get-FpacDeploymentInventory { $inventory }
        Mock New-FabricPolicySet { 'new-id' }
        Mock Update-FabricPolicySet {}
        Mock Remove-FabricPolicySet {}

        $result = Invoke-FpacDeployPolicyOperation -PlanFile $planPath `
            -GlobalSettingsPath $settingsPath `
            -EnvironmentName Test `
            -SchemaPath (Join-Path $PSScriptRoot '..\schemas\deployment-plan.schema.json') `
            -MaxRetryAttempts 2 `
            -Confirm:$false

        $result.Created | Should -Be 1
        $result.Updated | Should -Be 1
        $result.Replaced | Should -Be 1
        $result.Deleted | Should -Be 1
        Assert-MockCalled New-FabricPolicySet -Times 2
        Assert-MockCalled Update-FabricPolicySet -Times 1
        Assert-MockCalled Remove-FabricPolicySet -Times 2
    }
}
