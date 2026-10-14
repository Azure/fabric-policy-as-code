$scriptPath = Join-Path $PSScriptRoot '..\scripts\Deploy\Build-DeploymentPlans.ps1'
. $scriptPath

Describe 'FPAC deployment plans' {
    BeforeEach {
        Mock Write-FpacModernHeader {}
        Mock Write-FpacModernSection {}
        Mock Write-FpacModernStatus {}
        Mock Write-FpacModernCountSummary {}
        Mock Write-FpacDetailedChanges {}

        $script:desiredRoot = Join-Path $TestDrive 'desired'
        $script:deployedRoot = Join-Path $TestDrive 'deployed'
        foreach ($root in @($script:desiredRoot, $script:deployedRoot)) {
            if (Test-Path -LiteralPath $root) {
                Remove-Item -LiteralPath $root -Recurse -Force
            }
        }
        foreach ($folder in @('policyDefinitions', 'policySetDefinitions', 'policyAssignments')) {
            New-Item -ItemType Directory -Path (Join-Path $script:desiredRoot $folder) -Force | Out-Null
        }
        foreach ($folder in @('policyDefinitions', 'policySets', 'assignments')) {
            New-Item -ItemType Directory -Path (Join-Path $script:deployedRoot $folder) -Force | Out-Null
        }
        $script:target = [pscustomobject]@{
            Name       = 'Test'
            TenantId   = '11111111-1111-1111-1111-111111111111'
            ScopeType  = 'Capacity'
            CapacityId = '22222222-2222-2222-2222-222222222222'
            CapacityIds = @('22222222-2222-2222-2222-222222222222')
            Scopes = @([pscustomobject]@{
                Type = 'Capacity'
                Name = 'TestCapacity'
                CapacityId = '22222222-2222-2222-2222-222222222222'
            })
        }
    }

    It 'classifies new update replace delete and unchanged resources' {
        $unchanged = [ordered]@{
            '$schema' = '../../schemas/policy-definition.schema.json'
            name = 'unchanged'
            properties = [ordered]@{
                displayName = 'Unchanged'
                parameters = [ordered]@{}
                policy = 'ItemCreation'
                conditions = @()
                effects = @()
            }
        }
        Write-FpacJsonFile -Path (Join-Path $script:desiredRoot 'policyDefinitions\unchanged.json') -Value $unchanged
        Write-FpacJsonFile -Path (Join-Path $script:deployedRoot 'policyDefinitions\unchanged.json') -Value $unchanged

        $updatedDesired = [ordered]@{
            '$schema' = '../../schemas/policy-definition.schema.json'
            name = 'updated'
            properties = [ordered]@{
                displayName = 'Updated'
                description = 'Desired description'
                parameters = [ordered]@{}
                policy = 'ItemCreation'
                conditions = @()
                effects = @()
            }
        }
        $updatedDeployed = $updatedDesired | ConvertTo-Json -Depth 20 | ConvertFrom-Json
        $updatedDeployed.properties.description = 'Deployed description'
        Write-FpacJsonFile -Path (Join-Path $script:desiredRoot 'policyDefinitions\updated.json') -Value $updatedDesired
        Write-FpacJsonFile -Path (Join-Path $script:deployedRoot 'policyDefinitions\updated.json') -Value $updatedDeployed

        $replacementDesired = [ordered]@{
            '$schema' = '../../schemas/policy-definition.schema.json'
            name = 'replacement'
            properties = [ordered]@{
                displayName = 'Replacement'
                parameters = [ordered]@{}
                policy = 'ItemCreation'
                conditions = @()
                effects = @()
            }
        }
        $replacementDeployed = $replacementDesired | ConvertTo-Json -Depth 20 | ConvertFrom-Json
        $replacementDeployed.properties.policy = 'DataAccess'
        Write-FpacJsonFile -Path (Join-Path $script:desiredRoot 'policyDefinitions\replacement.json') -Value $replacementDesired
        Write-FpacJsonFile -Path (Join-Path $script:deployedRoot 'policyDefinitions\replacement.json') -Value $replacementDeployed

        $newDefinition = $unchanged | ConvertTo-Json -Depth 20 | ConvertFrom-Json
        $newDefinition.name = 'new'
        $newDefinition.properties.displayName = 'New'
        Write-FpacJsonFile -Path (Join-Path $script:desiredRoot 'policyDefinitions\new.json') -Value $newDefinition

        $deletedDefinition = $unchanged | ConvertTo-Json -Depth 20 | ConvertFrom-Json
        $deletedDefinition.name = 'deleted'
        $deletedDefinition.properties.displayName = 'Deleted'
        Write-FpacJsonFile -Path (Join-Path $script:deployedRoot 'policyDefinitions\deleted.json') -Value $deletedDefinition

        $policySet = [ordered]@{
            '$schema' = '../../schemas/policy-set.schema.json'
            name = 'set'
            properties = [ordered]@{
                displayName = 'Set'
                policies = @(
                    [ordered]@{ name = 'unchanged'; parameters = [ordered]@{} },
                    [ordered]@{ name = 'updated'; parameters = [ordered]@{} },
                    [ordered]@{ name = 'replacement'; parameters = [ordered]@{} },
                    [ordered]@{ name = 'new'; parameters = [ordered]@{} }
                )
            }
        }
        $deployedPolicySet = $policySet | ConvertTo-Json -Depth 20 | ConvertFrom-Json
        $deployedPolicySet.properties.policies = @(
            [pscustomobject]@{ name = 'unchanged'; parameters = [pscustomobject]@{} },
            [pscustomobject]@{ name = 'updated'; parameters = [pscustomobject]@{} },
            [pscustomobject]@{ name = 'replacement'; parameters = [pscustomobject]@{} },
            [pscustomobject]@{ name = 'deleted'; parameters = [pscustomobject]@{} }
        )
        Write-FpacJsonFile -Path (Join-Path $script:desiredRoot 'policySetDefinitions\set.json') -Value $policySet
        Write-FpacJsonFile -Path (Join-Path $script:deployedRoot 'policySets\set.json') -Value $deployedPolicySet

        $desiredAssignment = [ordered]@{
            '$schema' = '../../schemas/assignment.schema.json'
            name = 'assignment'
            properties = [ordered]@{
                environment = 'Test'
                policySetName = 'set'
                workspace = 'Test Workspace'
                displayName = 'Set'
                scope = [ordered]@{ type = 'Capacity'; id = $script:target.CapacityId }
                status = 'Active'
                parameters = [ordered]@{}
            }
        }
        $deployedAssignment = $desiredAssignment | ConvertTo-Json -Depth 20 | ConvertFrom-Json
        $deployedAssignment.properties.scope.id = '33333333-3333-3333-3333-333333333333'
        Write-FpacJsonFile -Path (Join-Path $script:desiredRoot 'policyAssignments\assignment.json') -Value $desiredAssignment
        Write-FpacJsonFile -Path (Join-Path $script:deployedRoot 'assignments\assignment.json') -Value $deployedAssignment

        $plan = New-FpacDeploymentPlan -DesiredRoot $script:desiredRoot `
            -DeployedRoot $script:deployedRoot -Target $script:target `
            -SchemaReference '../../schemas/deployment-plan.schema.json'

        $plan.policySets.update.Count | Should Be 1
        $plan.policySets.update.Contains('test-workspace-set') | Should Be $true
        ($plan.policySets.update['test-workspace-set'].changes -contains 'scope') | Should Be $true
        ($plan.policySets.update['test-workspace-set'].changes -contains 'policies') | Should Be $true
        $plan.numberOfChanges | Should Be 1
        $plan.numberUnchanged | Should Be 0

        $planJson = $plan | ConvertTo-Json -Depth 100
        Test-Json -Json $planJson -SchemaFile (Join-Path $PSScriptRoot '..\schemas\deployment-plan.schema.json') |
            Should Be $true
    }

    It 'writes changed plans and removes stale plans when no changes remain' {
        $planPath = Join-Path $TestDrive 'plans-Test\policy-plan.json'
        $changedPlan = [ordered]@{
            numberOfChanges = 1
            policyDefinitions = New-FpacPlanBucket
        }
        Write-FpacDeploymentPlan -Plan $changedPlan -Path $planPath | Should Be 'yes'
        Test-Path -LiteralPath $planPath | Should Be $true

        $unchangedPlan = [ordered]@{
            numberOfChanges = 0
            policyDefinitions = New-FpacPlanBucket
        }
        Write-FpacDeploymentPlan -Plan $unchangedPlan -Path $planPath | Should Be 'no'
        Test-Path -LiteralPath $planPath | Should Be $false
    }

    It 'selects desired resources through assignments for the target environment' {
        $definition = [ordered]@{
            '$schema' = '../../schemas/policy-definition.schema.json'
            name = 'selected-definition'
            properties = [ordered]@{
                displayName = 'Selected'
                parameters = [ordered]@{}
                policy = 'ItemCreation'
                conditions = @()
                effects = @()
            }
        }
        $otherDefinition = $definition | ConvertTo-Json -Depth 20 | ConvertFrom-Json
        $otherDefinition.name = 'other-definition'
        Write-FpacJsonFile -Path (Join-Path $script:desiredRoot 'policyDefinitions\selected.json') -Value $definition
        Write-FpacJsonFile -Path (Join-Path $script:desiredRoot 'policyDefinitions\other.json') -Value $otherDefinition

        $selectedSet = [ordered]@{
            '$schema' = '../../schemas/policy-set.schema.json'
            name = 'selected-set'
            properties = [ordered]@{
                displayName = 'Selected Set'
                policies = @([ordered]@{ name = 'selected-definition'; parameters = [ordered]@{} })
            }
        }
        $otherSet = [ordered]@{
            '$schema' = '../../schemas/policy-set.schema.json'
            name = 'other-set'
            properties = [ordered]@{
                displayName = 'Other Set'
                policies = @([ordered]@{ name = 'other-definition'; parameters = [ordered]@{} })
            }
        }
        Write-FpacJsonFile -Path (Join-Path $script:desiredRoot 'policySetDefinitions\selected.json') -Value $selectedSet
        Write-FpacJsonFile -Path (Join-Path $script:desiredRoot 'policySetDefinitions\other.json') -Value $otherSet

        $selectedAssignment = [ordered]@{
            '$schema' = '../../schemas/assignment.schema.json'
            name = 'selected-assignment'
            properties = [ordered]@{
                environment = 'Test'
                policySetName = 'selected-set'
                workspace = 'Test Workspace'
                displayName = 'Selected Set'
                scope = [ordered]@{ type = 'Capacity'; id = $script:target.CapacityId }
                status = 'Active'
                parameters = [ordered]@{}
            }
        }
        $otherAssignment = $selectedAssignment | ConvertTo-Json -Depth 20 | ConvertFrom-Json
        $otherAssignment.name = 'other-assignment'
        $otherAssignment.properties.environment = 'Other'
        $otherAssignment.properties.policySetName = 'other-set'
        Write-FpacJsonFile -Path (Join-Path $script:desiredRoot 'policyAssignments\selected.json') -Value $selectedAssignment
        Write-FpacJsonFile -Path (Join-Path $script:desiredRoot 'policyAssignments\other.json') -Value $otherAssignment

        $plan = New-FpacDeploymentPlan -DesiredRoot $script:desiredRoot `
            -DeployedRoot $script:deployedRoot -Target $script:target `
            -SchemaReference '../../schemas/deployment-plan.schema.json'

        $plan.policySets.new.Contains('test-workspace-selected-set') | Should Be $true
        $plan.policySets.new.Count | Should Be 1
        $plan.policySets.new['test-workspace-selected-set'].properties.policies.Count | Should Be 1
        $plan.policySets.new['test-workspace-selected-set'].properties.policies[0].name | Should Be 'Selected'
    }

    It 'fails when a selected assignment references a missing Policy Set definition' {
        $assignment = [ordered]@{
            '$schema' = '../../schemas/assignment.schema.json'
            name = 'broken'
            properties = [ordered]@{
                environment = 'Test'
                policySetName = 'missing'
                workspace = 'Test Workspace'
                displayName = 'Missing'
                scope = [ordered]@{ type = 'Capacity'; id = $script:target.CapacityId }
                status = 'Active'
                parameters = [ordered]@{}
            }
        }
        Write-FpacJsonFile -Path (Join-Path $script:desiredRoot 'policyAssignments\broken.json') -Value $assignment

        {
            New-FpacDeploymentPlan -DesiredRoot $script:desiredRoot `
                -DeployedRoot $script:deployedRoot -Target $script:target `
                -SchemaReference '../../schemas/deployment-plan.schema.json'
        } | Should Throw "Deployment 'broken' references missing Policy Set definition 'missing'."
    }

    It 'reports nested effective parameter additions and removals for Policy Sets' {
        $definition = [ordered]@{
            '$schema' = '../../schemas/policy-definition.schema.json'
            name = 'parameterized'
            properties = [ordered]@{
                displayName = 'Parameterized'
                parameters = [ordered]@{
                    condition1Values = [ordered]@{
                        type = 'Array'
                        defaultValue = @('Reflex', 'AnomalyDetector')
                        metadata = [ordered]@{}
                    }
                }

                policy = 'ItemCreation'
                conditions = @()
                effects = @()
            }
        }
        Write-FpacJsonFile -Path (Join-Path $script:desiredRoot 'policyDefinitions\parameterized.json') -Value $definition
        Write-FpacJsonFile -Path (Join-Path $script:deployedRoot 'policyDefinitions\parameterized.json') -Value $definition

        $desiredSet = [ordered]@{
            '$schema' = '../../schemas/policy-set.schema.json'
            name = 'set'
            properties = [ordered]@{
                displayName = 'Set'
                policies = @([ordered]@{
                    name = 'parameterized'
                    parameters = [ordered]@{}
                })
            }
        }
        $deployedSet = [ordered]@{
            '$schema' = '../../schemas/policy-set.schema.json'
            name = 'set'
            properties = [ordered]@{
                displayName = 'Set'
                policies = @([ordered]@{
                    name = 'parameterized'
                    parameters = [ordered]@{}
                })
            }
        }
        Write-FpacJsonFile -Path (Join-Path $script:desiredRoot 'policySetDefinitions\set.json') -Value $desiredSet
        Write-FpacJsonFile -Path (Join-Path $script:deployedRoot 'policySets\set.json') -Value $deployedSet

        $assignment = [ordered]@{
            '$schema' = '../../schemas/assignment.schema.json'
            name = 'assignment'
            properties = [ordered]@{
                environment = 'Test'
                policySetName = 'set'
                workspace = 'Test Workspace'
                displayName = 'Set'
                scope = [ordered]@{ type = 'Capacity'; id = $script:target.CapacityId }
                status = 'Active'
                parameters = [ordered]@{
                    parameterized = [ordered]@{
                        condition1Values = [ordered]@{ value = @('AnomalyDetector') }
                    }
                }
            }
        }
        Write-FpacJsonFile -Path (Join-Path $script:desiredRoot 'policyAssignments\assignment.json') -Value $assignment
        $deployedAssignment = $assignment | ConvertTo-Json -Depth 100 | ConvertFrom-Json
        $deployedAssignment.properties.parameters.parameterized.condition1Values.value = @('Reflex', 'AnomalyDetector')
        Write-FpacJsonFile -Path (Join-Path $script:deployedRoot 'assignments\assignment.json') -Value $deployedAssignment

        $plan = New-FpacDeploymentPlan -DesiredRoot $script:desiredRoot `
            -DeployedRoot $script:deployedRoot -Target $script:target `
            -SchemaReference '../../schemas/deployment-plan.schema.json'

        $plan.policySets.update.Count | Should Be 1
        $difference = @($plan.policySets.update['test-workspace-set'].differences | Where-Object {
            $_.change -eq 'Remove' -and $_.oldValue -eq 'Reflex'
        })
        $difference.Count | Should Be 1
        $difference[0].path | Should Be 'properties.policies[Parameterized].definition.parameters.condition1Values.defaultValue[]'

        Write-FpacPlanChangeDetails -ResourceType 'Policy Sets' `
            -ResourcePlan $plan.policySets -DetailedOutput
        Assert-MockCalled Write-FpacDetailedChanges -Times 1 -ParameterFilter {
            @($Differences | Where-Object {
                $_.change -eq 'Remove' -and $_.oldValue -eq 'Reflex'
            }).Count -eq 1
        }
    }

    It 'expands EPAC-style assignment children by FPAC environment with distinct parameters' {
        $assignmentDefinition = [pscustomobject]@{
            '$schema' = '../../schemas/assignment.schema.json'
            name = 'multi-capacity'
            properties = [pscustomobject]@{
                policySetName = 'set'
                children = @(
                    [pscustomobject]@{
                        name = 'first'
                        displayName = 'First'
                        parameters = [pscustomobject]@{
                            parameterized = [pscustomobject]@{
                                condition1Values = [pscustomobject]@{ value = @('A') }
                            }
                        }
                        targets = [pscustomobject]@{
                            Tenant = @([pscustomobject]@{
                                workspace = 'Test Workspace'
                                scope = [pscustomobject]@{ type = 'Capacity'; name = 'First'; id = 'capacity-1' }
                            })
                        }
                    },
                    [pscustomobject]@{
                        name = 'second'
                        displayName = 'Second'
                        status = 'Inactive'
                        parameters = [pscustomobject]@{
                            parameterized = [pscustomobject]@{
                                condition1Values = [pscustomobject]@{ value = @('B') }
                            }
                        }
                        targets = [pscustomobject]@{
                            Tenant = @([pscustomobject]@{
                                workspace = 'Other Workspace'
                                scope = [pscustomobject]@{ type = 'Capacity'; name = 'Second'; id = 'capacity-2' }
                            })
                            Other = @([pscustomobject]@{
                                workspace = 'Other Workspace'
                                scope = [pscustomobject]@{ type = 'Capacity'; name = 'Other'; id = 'capacity-3' }
                            })
                        }
                    }
                )
            }
        }

        $expanded = Expand-FpacAssignmentDefinitions `
            -AssignmentDefinitions ([ordered]@{ 'multi-capacity' = $assignmentDefinition }) `
            -EnvironmentName 'Tenant'

        $expanded.Count | Should Be 2
        $expanded.first.properties.environment | Should Be 'Tenant'
        $expanded.first.properties.scope.id | Should Be 'capacity-1'
        $expanded.first.properties.workspace | Should Be 'Test Workspace'
        $expanded.first.properties.status | Should Be 'Active'
        $expanded.first.properties.parameters.parameterized.condition1Values.value[0] | Should Be 'A'
        $expanded.second.properties.scope.id | Should Be 'capacity-2'
        $expanded.second.properties.workspace | Should Be 'Other Workspace'
        $expanded.second.properties.status | Should Be 'Inactive'
        $expanded.second.properties.parameters.parameterized.condition1Values.value[0] | Should Be 'B'

        $definition = [pscustomobject]@{
            name = 'parameterized'
            properties = [pscustomobject]@{
                displayName = 'Parameterized'
                parameters = [pscustomobject]@{
                    condition1Values = [pscustomobject]@{
                        type = 'Array'
                    }
                }
                policy = 'ItemCreation'
                conditions = @()
                effects = @()
            }
        }
        $policySet = [pscustomobject]@{
            name = 'set'
            properties = [pscustomobject]@{
                displayName = 'Set'
                policies = @([pscustomobject]@{
                    name = 'parameterized'
                    parameters = [pscustomobject]@{}
                })
            }
        }
        $materialized = New-FpacMaterializedPolicySets `
            -Assignments $expanded `
            -PolicySetDefinitions ([ordered]@{ set = $policySet }) `
            -PolicyDefinitions ([ordered]@{ parameterized = $definition })

        $materialized.Count | Should Be 2
        $materialized['test-workspace-first'].properties.policies[0].definition.parameters.condition1Values.defaultValue[0] |
            Should Be 'A'
        $materialized['other-workspace-second'].properties.policies[0].definition.parameters.condition1Values.defaultValue[0] |
            Should Be 'B'
    }

    It 'resolves portable workspace names to ids while materializing assignment parameters' {
        $assignments = [ordered]@{
            deployment = [pscustomobject]@{
                name = 'deployment'
                properties = [pscustomobject]@{
                    policySetName = 'set'
                    workspace = 'Governance'
                    displayName = 'Set'
                    status = 'Inactive'
                    scope = [pscustomobject]@{ type = 'Capacity'; id = 'capacity-id' }
                    parameters = [pscustomobject]@{
                        rule = [pscustomobject]@{
                            condition1Values = [pscustomobject]@{ value = @('Finance') }
                        }
                    }
                }
            }
        }
        $policySets = [ordered]@{
            set = [pscustomobject]@{
                name = 'set'
                properties = [pscustomobject]@{
                    displayName = 'Set'
                    policies = @([pscustomobject]@{ name = 'rule'; parameters = [pscustomobject]@{} })
                }
            }
        }
        $definitions = [ordered]@{
            rule = [pscustomobject]@{
                name = 'rule'
                properties = [pscustomobject]@{
                    displayName = 'Rule'
                    parameters = [pscustomobject]@{
                        condition1Values = [pscustomobject]@{
                            type = 'Array'
                            metadata = [pscustomobject]@{ targetProperty = 'workspace.id' }
                        }
                    }
                    policy = 'ItemCreation'
                    conditions = @()
                    effects = @()
                }
            }
        }
        $workspaceMap = [System.Collections.Hashtable]::new([System.StringComparer]::OrdinalIgnoreCase)
        $workspaceMap['Finance'] = 'workspace-id'

        $materialized = New-FpacMaterializedPolicySets `
            -Assignments $assignments -PolicySetDefinitions $policySets `
            -PolicyDefinitions $definitions -WorkspaceMap $workspaceMap

        $materialized['governance-set'].properties.policies[0].definition.parameters.condition1Values.defaultValue[0] |
            Should Be 'workspace-id'
    }

    It 'requires every declared policy parameter in the deployment assignment' {
        $policySet = [pscustomobject]@{
            name = 'set'
            properties = [pscustomobject]@{
                displayName = 'Set'
                policies = @([pscustomobject]@{ name = 'rule'; parameters = [pscustomobject]@{} })
            }
        }
        $definition = [pscustomobject]@{
            name = 'rule'
            properties = [pscustomobject]@{
                displayName = 'Rule'
                parameters = [pscustomobject]@{
                    requiredValue = [pscustomobject]@{ type = 'Array'; metadata = [pscustomobject]@{} }
                }
                policy = 'ItemCreation'
                conditions = @()
                effects = @()
            }
        }
        $assignment = [pscustomobject]@{
            name = 'deployment'
            properties = [pscustomobject]@{
                policySetName = 'set'
                workspace = 'Governance'
                displayName = 'Set'
                status = 'Inactive'
                scope = [pscustomobject]@{ type = 'Capacity'; id = 'capacity-id' }
                parameters = [pscustomobject]@{}
            }
        }
        $threw = $false
        try {
            New-FpacMaterializedPolicySets `
                -Assignments ([ordered]@{ deployment = $assignment }) `
                -PolicySetDefinitions ([ordered]@{ set = $policySet }) `
                -PolicyDefinitions ([ordered]@{ rule = $definition }) | Out-Null
        }
        catch {
            $threw = $_.Exception.Message -like "*deployment assignment did not supply a value."
        }
        $threw | Should Be $true
    }

    It 'resolves capacity assignment scopes by name' {
        $assignmentDefinition = [pscustomobject]@{
            '$schema' = '../../schemas/assignment.schema.json'
            name = 'named-capacity'
            properties = [pscustomobject]@{
                policySetName = 'set'
                children = @([pscustomobject]@{
                    name = 'named'
                    displayName = 'Named'
                    targets = [pscustomobject]@{
                        Tenant = @([pscustomobject]@{
                            workspace = 'Test Workspace'
                            scope = [pscustomobject]@{ type = 'Capacity'; name = 'Finance' }
                        })
                    }
                })
            }
        }

        $expanded = Expand-FpacAssignmentDefinitions `
            -AssignmentDefinitions ([ordered]@{ 'named-capacity' = $assignmentDefinition }) `
            -EnvironmentName 'Tenant' `
            -CapacityMap @{ Finance = '11111111-1111-1111-1111-111111111111' }

        $expanded.named.properties.scope.id | Should Be '11111111-1111-1111-1111-111111111111'
        @($expanded.named.properties.scope.PSObject.Properties.Name) | Should Be @('type', 'id')
    }

    It 'fans one child out across workspace and scope target pairs' {
        $assignmentDefinition = [pscustomobject]@{
            '$schema' = '../../schemas/assignment.schema.json'
            name = 'fan-out'
            properties = [pscustomobject]@{
                policySetName = 'set'
                children = @([pscustomobject]@{
                    name = 'shared'
                    displayName = 'Shared Policy Set'
                    targets = [pscustomobject]@{
                        Tenant = @(
                            [pscustomobject]@{
                                workspace = 'Workspace One'
                                scope = [pscustomobject]@{ name = 'First' }
                            },
                            [pscustomobject]@{
                                workspace = 'Workspace Two'
                                scope = [pscustomobject]@{ type = 'Tenant' }
                            }
                        )
                    }
                })
            }
        }

        $expanded = Expand-FpacAssignmentDefinitions `
            -AssignmentDefinitions ([ordered]@{ 'fan-out' = $assignmentDefinition }) `
            -EnvironmentName 'Tenant' `
            -CapacityMap @{ First = '11111111-1111-1111-1111-111111111111' }

        $expanded.Count | Should Be 2
        $expanded.Contains('shared-workspace-one-first') | Should Be $true
        $expanded.Contains('shared-workspace-two-tenant') | Should Be $true
    }

    It 'infers a name-only assignment scope is a capacity' {
        $resolved = Resolve-FpacAssignmentScope `
            -Scope ([pscustomobject]@{ name = 'Finance' }) `
            -CapacityMap @{ Finance = '11111111-1111-1111-1111-111111111111' }

        $resolved.type | Should Be 'Capacity'
        $resolved.id | Should Be '11111111-1111-1111-1111-111111111111'
    }

    It 'fails clearly when a capacity name cannot be resolved' {
        {
            Resolve-FpacAssignmentScope `
                -Scope ([pscustomobject]@{ type = 'Capacity'; name = 'Missing' }) `
                -CapacityMap @{}
        } | Should Throw "Capacity 'Missing' was not returned by Fabric and is not configured in global settings."
    }

    It 'rejects assignments outside a capacity environment' {
        $assignments = [ordered]@{
            outside = [pscustomobject]@{
                name = 'outside'
                properties = [pscustomobject]@{
                    scope = [pscustomobject]@{
                        type = 'Capacity'
                        id = '33333333-3333-3333-3333-333333333333'
                    }
                }
            }
        }

        $threw = $false
        try {
            Assert-FpacAssignmentsWithinEnvironment -Assignments $assignments -Target $script:target
        }
        catch {
            $threw = $_.Exception.Message -like "*outside capacity environment '$($script:target.Name)'*"
        }
        $threw | Should Be $true
    }

    It 'rejects deployment targets whose workspace is not accessible' {
        $assignments = [ordered]@{
            missing = [pscustomobject]@{
                name = 'missing'
                properties = [pscustomobject]@{
                    workspace = 'Missing Workspace'
                }
            }
        }

        {
            Assert-FpacDeploymentWorkspaces `
                -Assignments $assignments `
                -WorkspaceMap ([System.Collections.Hashtable]::new([System.StringComparer]::OrdinalIgnoreCase))
        } | Should Throw "Workspace 'Missing Workspace' targeted by Policy Set deployment 'missing' was not returned by Fabric. Verify the workspace name and access for the planning identity."
    }

    It 'matches deployment target workspace names case-insensitively' {
        $assignments = [ordered]@{
            found = [pscustomobject]@{
                name = 'found'
                properties = [pscustomobject]@{
                    workspace = 'policytest'
                }
            }
        }
        $workspaceMap = [System.Collections.Hashtable]::new([System.StringComparer]::OrdinalIgnoreCase)
        $workspaceMap['PolicyTest'] = 'workspace-id'

        Assert-FpacDeploymentWorkspaces -Assignments $assignments -WorkspaceMap $workspaceMap
    }

    It 'rejects a target workspace that is not assigned to a capacity' {
        $assignments = [ordered]@{
            found = [pscustomobject]@{
                name = 'found'
                properties = [pscustomobject]@{ workspace = 'My workspace' }
            }
        }
        $workspaceMap = [System.Collections.Hashtable]::new([System.StringComparer]::OrdinalIgnoreCase)
        $workspaceMap['My workspace'] = 'workspace-id'
        $workspaceDetails = [System.Collections.Hashtable]::new([System.StringComparer]::OrdinalIgnoreCase)
        $workspaceDetails['My workspace'] = [pscustomobject]@{ Id = 'workspace-id'; CapacityId = '' }

        {
            Assert-FpacDeploymentWorkspaces -Assignments $assignments `
                -WorkspaceMap $workspaceMap -WorkspaceDetails $workspaceDetails
        } | Should Throw "Workspace 'My workspace' targeted by Policy Set deployment 'found' is not assigned to a Fabric capacity. Policy Sets can only be stored in capacity-backed workspaces."
    }

    It 'rejects more than one desired active Policy Set for the same scope' {
        $sets = [ordered]@{
            one = [pscustomobject]@{
                name = 'one'
                properties = [pscustomobject]@{
                    status = 'Active'
                    scope = [pscustomobject]@{ type = 'Capacity'; id = $script:target.CapacityId }
                }
            }
            two = [pscustomobject]@{
                name = 'two'
                properties = [pscustomobject]@{
                    status = 'Active'
                    scope = [pscustomobject]@{ type = 'Capacity'; id = $script:target.CapacityId }
                }
            }
        }

        $threw = $false
        try {
            Assert-FpacActivePolicySetScopes -PolicySets $sets
        }
        catch {
            $threw = $_.Exception.Message -like '*Only one Policy Set can be active per administrative scope.'
        }
        $threw | Should Be $true
    }

    It 'adopts matching unowned resources and preserves unrelated unowned resources by default' {
        $desired = [ordered]@{
            managed = [pscustomobject]@{
                name = 'managed'
                metadata = [pscustomobject]@{ pacOwnerId = 'owner-one' }
                properties = [pscustomobject]@{ displayName = 'Managed' }
            }
        }
        $deployed = [ordered]@{
            managed = [pscustomobject]@{
                name = 'managed'
                metadata = [pscustomobject]@{ pacOwnerId = '' }
                properties = [pscustomobject]@{ displayName = 'Managed' }
            }
            manual = [pscustomobject]@{
                name = 'manual'
                metadata = [pscustomobject]@{ pacOwnerId = '' }
                properties = [pscustomobject]@{ displayName = 'Manual' }
            }
        }

        $plan = Build-FpacResourcePlan -ResourceType 'Policy Sets' -Desired $desired `
            -Deployed $deployed -PacOwnerId 'owner-one' -DesiredStateStrategy OwnedOnly

        $plan.adopt.Count | Should Be 1
        $plan.delete.Count | Should Be 0
    }

    It 'detects active scope conflicts across FPAC environments' {
        $definitions = [ordered]@{
            declaration = [pscustomobject]@{
                name = 'declaration'
                properties = [pscustomobject]@{
                    policySetName = 'set'
                    children = @(
                        [pscustomobject]@{
                            name = 'one'
                            status = 'Active'
                            targets = [pscustomobject]@{
                                EnvOne = @([pscustomobject]@{
                                    workspace = 'One'
                                    scope = [pscustomobject]@{ name = 'SharedCapacity' }
                                })
                            }
                        },
                        [pscustomobject]@{
                            name = 'two'
                            status = 'Active'
                            targets = [pscustomobject]@{
                                EnvTwo = @([pscustomobject]@{
                                    workspace = 'Two'
                                    scope = [pscustomobject]@{ name = 'sharedcapacity' }
                                })
                            }
                        }
                    )
                }
            }
        }
        $environments = @(
            [pscustomobject]@{ Name = 'EnvOne'; TenantId = $script:target.TenantId },
            [pscustomobject]@{ Name = 'EnvTwo'; TenantId = $script:target.TenantId }
        )

        $threw = $false
        try {
            Assert-FpacCrossEnvironmentActiveScopes `
                -AssignmentDefinitions $definitions -Environments $environments
        }
        catch {
            $threw = $_.Exception.Message -like '*both target*'
        }
        $threw | Should Be $true
    }

    It 'resolves environment capacity names from live Fabric capacities' {
        Mock Get-FabricPagedCollection {
            return @([pscustomobject]@{
                id = '11111111-1111-1111-1111-111111111111'
                displayName = 'Live'
            })
        }

        $map = Get-FpacCapacityMap -Headers @{ Authorization = '******' }
        $target = [pscustomobject]@{
            Name = 'Team'
            TenantId = '22222222-2222-2222-2222-222222222222'
            ScopeType = 'Capacity'
            Scopes = @([pscustomobject]@{ Type = 'Capacity'; Name = 'Live'; CapacityId = $null })
            CapacityIds = @()
        }
        $resolved = Resolve-FpacEnvironmentCapacityScopes -Target $target -CapacityMap $map

        $map.Live | Should Be '11111111-1111-1111-1111-111111111111'
        $resolved.CapacityIds[0] | Should Be '11111111-1111-1111-1111-111111111111'
        $resolved.Scopes[0].Name | Should Be 'Live'
    }

    It 'excludes fake assignment samples from artifact discovery' {
        $samplePath = Join-Path $script:desiredRoot 'policyAssignments\sample.fake'
        Set-Content -LiteralPath $samplePath -Value '{ "name": "sample" }' -Encoding utf8

        $assignments = Get-FpacArtifactCollection -Path (Join-Path $script:desiredRoot 'policyAssignments')

        $assignments.Count | Should Be 0
    }

    It 'builds the plan file through the operation workflow' {
        $definitionsRoot = Join-Path $TestDrive 'definitions'
        foreach ($folder in @('policyDefinitions', 'policySetDefinitions', 'policyAssignments')) {
            New-Item -ItemType Directory -Path (Join-Path $definitionsRoot $folder) -Force | Out-Null
        }
        $definition = [ordered]@{
            '$schema' = '../../schemas/policy-definition.schema.json'
            name = 'new'
            properties = [ordered]@{
                displayName = 'New'
                parameters = [ordered]@{}
                policy = 'ItemCreation'
                conditions = @()
                effects = @()
            }
        }
        Write-FpacJsonFile -Path (Join-Path $definitionsRoot 'policyDefinitions\new.json') -Value $definition
        $policySet = [ordered]@{
            '$schema' = '../../schemas/policy-set.schema.json'
            name = 'set'
            properties = [ordered]@{
                displayName = 'Set'
                policies = @([ordered]@{ name = 'new'; parameters = [ordered]@{} })
            }
        }
        Write-FpacJsonFile -Path (Join-Path $definitionsRoot 'policySetDefinitions\set.json') -Value $policySet
        $assignment = [ordered]@{
            '$schema' = '../../schemas/assignment.schema.json'
            name = 'assignment'
            properties = [ordered]@{
                environment = $script:target.Name
                policySetName = 'set'
                workspace = 'Test Workspace'
                displayName = 'Set'
                scope = [ordered]@{ type = 'Capacity'; id = $script:target.CapacityId }
                status = 'Active'
                parameters = [ordered]@{}
            }
        }
        Write-FpacJsonFile -Path (Join-Path $definitionsRoot 'policyAssignments\assignment.json') -Value $assignment

        Mock Get-FpacGlobalSettings {
            return [pscustomobject]@{ Environments = @($script:target) }
        }
        Mock Select-FpacEnvironment {
            return $script:target
        }
        Mock Get-FabricAuthenticationHeaders {
            return @{ Authorization = '******' }
        }
        Mock Get-FpacCapacityMap {
            return @{ TestCapacity = $script:target.CapacityId }
        }
        Mock Invoke-FabricPolicyExport {
            foreach ($folder in @('policyDefinitions', 'policySets', 'assignments')) {
                New-Item -ItemType Directory -Path (Join-Path $Destination $folder) -Force | Out-Null
            }
            return [pscustomobject]@{
                IsComplete = $true
                FailureCount = 0
                PolicyCount = 0
                ExportedCount = 0
                WorkspaceMap = @{ 'Test Workspace' = 'workspace-id' }
            }
        }

        $outputRoot = Join-Path $TestDrive 'output'
        $result = Invoke-FpacBuildDeploymentPlansOperation `
            -DefinitionsPath $definitionsRoot `
            -OutputPath $outputRoot `
            -GlobalSettingsPath (Join-Path $TestDrive 'settings.jsonc') `
            -EnvironmentName $script:target.Name `
            -DevOpsType none `
            -MaxRetryAttempts 5

        $result.PolicyStage | Should Be 'yes'
        Assert-MockCalled Invoke-FabricPolicyExport -Times 1 -Exactly -ParameterFilter {
            $ActivityVerb -eq 'Retrieving'
        }
        Assert-MockCalled Get-FpacCapacityMap -Times 1 -Exactly
        Assert-MockCalled Write-FpacModernSection -Times 1 -ParameterFilter {
            $Title -eq 'Policy Sets Change Details'
        }
        Test-Path -LiteralPath $result.PlanFile | Should Be $true
        $planJson = Get-Content -LiteralPath $result.PlanFile -Raw
        $plan = $planJson | ConvertFrom-Json
        $newPolicySet = $plan.policySets.new.PSObject.Properties['test-workspace-set'].Value
        $newPolicySet.properties.policies[0].name | Should Be 'New'
        [System.IO.Path]::GetFullPath((Join-Path (Split-Path -Parent $result.PlanFile) $plan.'$schema')) |
            Should Be ([System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\schemas\deployment-plan.schema.json')))
        Test-Json -Json $planJson -SchemaFile (Join-Path $PSScriptRoot '..\schemas\deployment-plan.schema.json') |
            Should Be $true
    }
}
