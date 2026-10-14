BeforeAll {
    $scriptPath = Join-Path $PSScriptRoot '..\scripts\operations\Export-PolicyToFPAC.ps1'
    . $scriptPath
}

Describe 'Invoke-FabricPolicyExport' {
    BeforeEach {
        $script:headers = @{ Authorization = 'Bearer test-token' }
        $script:target = [pscustomobject]@{
            Name = 'CapacityTest'
            TenantId = '11111111-1111-1111-1111-111111111111'
            ScopeType = 'Capacity'
            CapacityId = '33333333-3333-3333-3333-333333333333'
            CapacityIds = @('33333333-3333-3333-3333-333333333333')
            Scopes = @([pscustomobject]@{
                Type = 'Capacity'
                Name = 'CapacityTest'
                CapacityId = '33333333-3333-3333-3333-333333333333'
            })
        }
        $script:capacityMap = @{ CapacityTest = $script:target.CapacityId }
        $script:workspaceResponse = [pscustomobject]@{
            StatusCode = 200
            Headers = @{}
            Body = [pscustomobject]@{
                value = @([pscustomobject]@{
                    id = 'workspace-1'
                    displayName = 'Finance'
                })
            }
        }
        $script:itemResponse = [pscustomobject]@{
            StatusCode = 200
            Headers = @{}
            Body = [pscustomobject]@{
                value = @(
                    [pscustomobject]@{
                        id = 'policy-1'
                        displayName = 'Allow item creation'
                        type = 'PolicySet'
                    },
                    [pscustomobject]@{
                        id = 'lakehouse-1'
                        displayName = 'Sales'
                        type = 'Lakehouse'
                    }
                )
            }
        }
        $script:policySetResponse = [pscustomobject]@{
            StatusCode = 200
            Headers = @{}
            Body = [pscustomobject]@{
                id = 'policy-1'
                displayName = 'Allow item creation'
                type = 'PolicySet'
                workspaceId = 'workspace-1'
                properties = [pscustomobject]@{
                    scope = [pscustomobject]@{
                        type = 'Capacity'
                        id = $script:target.CapacityId
                    }
                    status = 'Active'
                }
            }
        }
        $script:rulesResponse = [pscustomobject]@{
            StatusCode = 200
            Headers = @{}
            Body = [pscustomobject]@{
                value = @(
                    [pscustomobject]@{
                        id = '5e4f0002-ad1b-417c-84eb-85e678e7916a'
                        displayName = 'Allow finance workspace'
                        description = 'Limit to finance.'
                        policy = 'ItemCreation'
                        createdDateTime = '2026-10-09T17:21:00Z'
                        lastModifiedDateTime = '2026-10-09T17:21:00Z'
                        conditions = @([pscustomobject]@{
                            type = 'Dynamic'
                            targetProperty = 'workspace.id'
                            predicate = [pscustomobject]@{
                                operator = 'AnyOf'
                                values = @('workspace-1')
                            }
                        })
                        effects = @([pscustomobject]@{ type = 'Allow' })
                    },
                    [pscustomobject]@{
                        id = '265f0002-75cb-41e4-be5c-41f25edcce4d'
                        displayName = 'Allow selected item types'
                        description = 'Only allow selected item kinds.'
                        policy = 'ItemCreation'
                        conditions = @([pscustomobject]@{
                            type = 'Dynamic'
                            targetProperty = 'item.type'
                            predicate = [pscustomobject]@{
                                operator = 'AnyOf'
                                values = @('Reflex', 'AnomalyDetector')
                            }
                        })
                        effects = @([pscustomobject]@{ type = 'Allow' })
                    }
                )
            }
        }

        Mock Invoke-FabricApiRequest {
            if ($Uri -match '/workspaces$') {
                return $script:workspaceResponse
            }
            if ($Uri -match '/workspaces/workspace-1/items$') {
                return $script:itemResponse
            }
            if ($Uri -match '/workspaces/workspace-1/policySets/policy-1/policyRules\?beta=true$') {
                return $script:rulesResponse
            }
            if ($Uri -match '/workspaces/workspace-1/policySets/policy-1$') {
                return $script:policySetResponse
            }
            throw "Unexpected Fabric API request: $Method $Uri"
        }
    }

    It 'exports rules as parameterized policy files and creates a policy set and scope assignment' {
        $output = Join-Path $TestDrive 'export'
        $result = Invoke-FabricPolicyExport -Headers $script:headers -Destination $output `
            -Target $script:target -CapacityMap $script:capacityMap

        $result.IsComplete | Should -Be $true
        $result.ExportedCount | Should -Be 1
        $result.PolicyCount | Should -Be 2
        $result.FailureCount | Should -Be 0

        $policyFiles = @(Get-ChildItem -LiteralPath (Join-Path $output 'policyDefinitions') -Filter '*.json')
        $policyFiles.Count | Should -Be 2
        $policyJson = Get-Content -LiteralPath $policyFiles[0].FullName -Raw
        $policy = $policyJson | ConvertFrom-Json
        $policy.name | Should -Match 'allow-.*'
        @($policy.PSObject.Properties.Name) | Should -Be @('$schema', 'name', 'properties')
        $policy.'$schema' | Should -Be (Get-FpacSchemaReference `
            -ArtifactDirectory $policyFiles[0].DirectoryName `
            -SchemaPath (Join-Path $PSScriptRoot '..\schemas\policy-definition.schema.json'))
        $policy.properties.parameters.condition1Values.type | Should -Be 'Array'
        $null -eq $policy.properties.parameters.condition1Values.PSObject.Properties['defaultValue'] |
            Should -Be $true
        $policy.properties.conditions[0].predicate.values[0] | Should -Match '^\[parameters\('
        $policyJson | Should -Not -Match '"fabricRuleId"|"createdDateTime"|"lastModifiedDateTime"'
        (Test-Json -Json $policyJson -SchemaFile (Join-Path $PSScriptRoot '..\schemas\policy-definition.schema.json')) | Should -Be $true

        $policySetFile = Get-ChildItem -LiteralPath (Join-Path $output 'policySets') -Filter '*.json'
        $policySet = Get-Content -LiteralPath $policySetFile.FullName -Raw | ConvertFrom-Json
        $policySet.name | Should -Match 'allow-item-creation-.*'
        @($policySet.PSObject.Properties.Name) | Should -Be @('$schema', 'name', 'properties')
        $policySet.'$schema' | Should -Be (Get-FpacSchemaReference `
            -ArtifactDirectory $policySetFile.DirectoryName `
            -SchemaPath (Join-Path $PSScriptRoot '..\schemas\policy-set.schema.json'))
        ($policySet.properties.PSObject.Properties.Name -notcontains 'scope') | Should -Be $true
        ($policySet.properties.PSObject.Properties.Name -notcontains 'metadata') | Should -Be $true
        $policySet.properties.policies.Count | Should -Be 2
        $policySet.properties.policies[0].parameters | Should -BeOfType System.Management.Automation.PSCustomObject
        @($policySet.properties.policies | Where-Object {
            @($_.parameters.PSObject.Properties).Count -gt 0
        }).Count | Should -Be 0
        (Test-Json -Json (Get-Content -LiteralPath $policySetFile.FullName -Raw) -SchemaFile (Join-Path $PSScriptRoot '..\schemas\policy-set.schema.json')) | Should -Be $true

        $assignmentFile = Get-ChildItem -LiteralPath (Join-Path $output 'assignments') -Filter '*.json'
        $assignmentJson = Get-Content -LiteralPath $assignmentFile.FullName -Raw
        $assignment = $assignmentJson | ConvertFrom-Json
        @($assignment.PSObject.Properties.Name) | Should -Be @('$schema', 'name', 'properties')
        $assignment.'$schema' | Should -Be (Get-FpacSchemaReference `
            -ArtifactDirectory $assignmentFile.DirectoryName `
            -SchemaPath (Join-Path $PSScriptRoot '..\schemas\assignment.schema.json'))
        $assignment.properties.policySetName | Should -Be $policySet.name
        ($null -eq $assignment.properties.PSObject.Properties['children']) | Should -Be $true
        $assignment.properties.displayName | Should -Be 'Allow item creation'
        $exportedTarget = $assignment.properties.targets.CapacityTest[0]
        $exportedTarget.workspace | Should -Be 'Finance'
        $exportedTarget.scope.name | Should -Be 'CapacityTest'
        $assignment.properties.status | Should -Be 'Active'
        $assignment.properties.parameters | Should -BeOfType System.Management.Automation.PSCustomObject
        foreach ($exportedPolicy in @($policySet.properties.policies)) {
            $parameterValues = $assignment.properties.parameters.PSObject.Properties[$exportedPolicy.name].Value
            @($parameterValues.condition1Values.value).Count | Should -BeGreaterThan 0
        }
        @($assignment.properties.parameters.PSObject.Properties | Where-Object {
            @($_.Value.condition1Values.value) -contains 'Finance'
        }).Count | Should -Be 1
        $assignmentJson | Should -Not -Match '"workspace-1"'
        $assignmentJson | Should -Not -Match '"metadata"|"fabricPolicySetId"|"exportedAtUtc"'
        (Test-Json -Json $assignmentJson -SchemaFile (Join-Path $PSScriptRoot '..\schemas\assignment.schema.json')) | Should -Be $true
        $expandedAssignment = Expand-FpacAssignmentDefinitions `
            -AssignmentDefinitions ([ordered]@{ $assignment.name = $assignment }) `
            -EnvironmentName $script:target.Name `
            -CapacityMap $script:capacityMap
        $expandedAssignment[$assignment.name].properties.scope.id | Should -Be $script:target.CapacityId

        $manifest = Get-Content -LiteralPath (Join-Path $output 'manifest.json') -Raw | ConvertFrom-Json
        $manifest.environment.name | Should -Be $script:target.Name
        $manifest.policyCount | Should -Be 2
        $manifest.policySets[0].policyCount | Should -Be 2
        Test-Path -LiteralPath (Join-Path $output 'schemas') | Should -Be $false
    }

    It 'exports all policy scopes when the selected environment is tenant-wide' {
        $script:target.Name = 'Tenant'
        $script:target.ScopeType = 'Tenant'
        $script:target.CapacityId = $null
        $script:target.CapacityIds = @()
        $script:target.Scopes = @([pscustomobject]@{ Type = 'Tenant'; CapacityId = $null })
        $script:policySetResponse.Body.properties.scope.type = 'Capacity'
        $script:policySetResponse.Body.properties.scope.id = '33333333-3333-3333-3333-333333333333'

        $output = Join-Path $TestDrive 'tenant-export'
        $result = Invoke-FabricPolicyExport -Headers $script:headers -Destination $output `
            -Target $script:target -CapacityMap $script:capacityMap

        $result.ExportedCount | Should -Be 1
        $manifest = Get-Content -LiteralPath (Join-Path $output 'manifest.json') -Raw | ConvertFrom-Json
        $manifest.policySets[0].scopeType | Should -Be 'Capacity'
    }

    It 'skips capacity policy sets assigned to another capacity' {
        $script:policySetResponse.Body.properties.scope.id = '44444444-4444-4444-4444-444444444444'

        $output = Join-Path $TestDrive 'capacity-filter'
        $result = Invoke-FabricPolicyExport -Headers $script:headers -Destination $output `
            -Target $script:target -CapacityMap $script:capacityMap

        $result.ExportedCount | Should -Be 0
        $manifest = Get-Content -LiteralPath (Join-Path $output 'manifest.json') -Raw | ConvertFrom-Json
        $manifest.skippedScopeCount | Should -Be 1
        $manifest.failureCount | Should -Be 0
    }

    It 'rejects duplicate accessible workspace names' {
        $script:workspaceResponse.Body.value = @(
            [pscustomobject]@{ id = 'workspace-1'; displayName = 'PolicyTest' },
            [pscustomobject]@{ id = 'workspace-2'; displayName = 'policytest' }
        )

        $output = Join-Path $TestDrive 'duplicate-workspaces'
        {
            Invoke-FabricPolicyExport -Headers $script:headers -Destination $output `
                -Target $script:target -CapacityMap $script:capacityMap
        } | Should -Throw "Fabric returned more than one accessible workspace named 'policytest'. FPAC deployment target workspace names must be unique."
    }

    It 'exports policy sets assigned to any capacity in the selected environment' {
        $secondCapacityId = '44444444-4444-4444-4444-444444444444'
        $script:target.CapacityIds = @($script:target.CapacityId, $secondCapacityId)
        $script:target.Scopes = @(
            $script:target.Scopes[0],
            [pscustomobject]@{ Type = 'Capacity'; Name = 'SecondCapacity'; CapacityId = $secondCapacityId }
        )
        $script:capacityMap.SecondCapacity = $secondCapacityId
        $script:policySetResponse.Body.properties.scope.id = $secondCapacityId

        $output = Join-Path $TestDrive 'multi-capacity-filter'
        $result = Invoke-FabricPolicyExport -Headers $script:headers -Destination $output `
            -Target $script:target -CapacityMap $script:capacityMap

        $result.ExportedCount | Should -Be 1
        $manifest = Get-Content -LiteralPath (Join-Path $output 'manifest.json') -Raw | ConvertFrom-Json
        $manifest.environment.scopes.Count | Should -Be 2
    }

    It 'reports policy set and policy rule API failures in the manifest' {
        Mock Invoke-FabricApiRequest {
            if ($Uri -match '/workspaces$') {
                return $script:workspaceResponse
            }
            if ($Uri -match '/workspaces/workspace-1/items$') {
                return $script:itemResponse
            }
            if ($Uri -match '/workspaces/workspace-1/policySets/policy-1$') {
                throw 'Policy Set access denied.'
            }
            throw "Unexpected Fabric API request: $Method $Uri"
        }

        $output = Join-Path $TestDrive 'partial'
        $result = Invoke-FabricPolicyExport -Headers $script:headers -Destination $output `
            -Target $script:target -CapacityMap $script:capacityMap

        $result.IsComplete | Should -Be $false
        $result.FailureCount | Should -Be 1
        $manifest = Get-Content -LiteralPath (Join-Path $output 'manifest.json') -Raw | ConvertFrom-Json
        $manifest.failures[0].itemId | Should -Be 'policy-1'
        $manifest.isComplete | Should -Be $false
    }

    It 'refuses to write into a non-empty output directory' {
        $output = Join-Path $TestDrive 'occupied'
        New-Item -ItemType Directory -Path $output | Out-Null
        Set-Content -LiteralPath (Join-Path $output 'keep.txt') -Value 'keep'

        $threw = $false
        try {
            Invoke-FabricPolicyExport -Headers $script:headers -Destination $output `
                -Target $script:target -CapacityMap $script:capacityMap
        }
        catch {
            $threw = $_.Exception.Message -like '*not empty*'
        }
        $threw | Should -Be $true
        Test-Path -LiteralPath (Join-Path $output 'keep.txt') | Should -Be $true
    }
}

Describe 'FPAC output replacement' {
    It 'adds the environment folder when OutputPath is the output root' {
        $root = Join-Path $TestDrive 'Output'

        $destination = Resolve-FpacScopeOutputPath -OutputRoot $root -ScopeName 'CapacityTest'

        $destination | Should -Be ([System.IO.Path]::GetFullPath((Join-Path $root 'CapacityTest')))
    }

    It 'uses the environment folder directly when OutputPath already ends with its name' {
        $environmentFolder = Join-Path (Join-Path $TestDrive 'Output') 'CapacityTest'

        $destination = Resolve-FpacScopeOutputPath -OutputRoot $environmentFolder -ScopeName 'CapacityTest'

        $destination | Should -Be ([System.IO.Path]::GetFullPath($environmentFolder))
    }

    It 'does not prompt when the selected scope output folder does not exist' {
        Mock Read-Host { throw 'Should not prompt when there is no existing output.' }
        $destination = Join-Path (Join-Path $TestDrive 'Output') 'CapacityTest'

        $result = Confirm-FpacOutputReplacement -DestinationPath $destination -DisplayPath 'Output\CapacityTest'

        $result | Should -Be $true
        Test-Path -LiteralPath $destination | Should -Be $false
    }

    It 'deletes only the selected scope folder after Y confirmation' {
        $root = Join-Path $TestDrive 'Output'
        $scopeFolder = Join-Path $root 'CapacityTest'
        New-Item -ItemType Directory -Path $scopeFolder -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $scopeFolder 'keep.txt') -Value 'replace'
        Mock Read-Host { return 'Y' }

        $result = Confirm-FpacOutputReplacement -DestinationPath $scopeFolder -DisplayPath 'Output\CapacityTest'

        $result | Should -Be $true
        Test-Path -LiteralPath $scopeFolder | Should -Be $false
    }

    It 'preserves the existing scope folder after N confirmation' {
        $root = Join-Path $TestDrive 'Output'
        $scopeFolder = Join-Path $root 'CapacityTest'
        New-Item -ItemType Directory -Path $scopeFolder -Force | Out-Null
        $marker = Join-Path $scopeFolder 'keep.txt'
        Set-Content -LiteralPath $marker -Value 'preserve'
        Mock Read-Host { return 'N' }

        $result = Confirm-FpacOutputReplacement -DestinationPath $scopeFolder -DisplayPath 'Output\CapacityTest'

        $result | Should -Be $false
        (Get-Content -LiteralPath $marker -Raw).Trim() | Should -Be 'preserve'
    }
}

Describe 'Get-FabricPagedCollection' {
    It 'follows continuation tokens until all pages are collected' {
        $script:pageCalls = [System.Collections.Generic.List[string]]::new()
        Mock Invoke-FabricApiRequest {
            $script:pageCalls.Add($Uri)
            if ($Uri -eq 'https://api.fabric.microsoft.com/v1/workspaces') {
                return [pscustomobject]@{
                    StatusCode = 200
                    Headers = @{}
                    Body = [pscustomobject]@{
                        value = @([pscustomobject]@{ id = 'w1' })
                        continuationToken = 'token/2'
                    }
                }
            }
            return [pscustomobject]@{
                StatusCode = 200
                Headers = @{}
                Body = [pscustomobject]@{
                    value = @([pscustomobject]@{ id = 'w2' })
                }
            }
        }

        $results = @(Get-FabricPagedCollection -Uri 'https://api.fabric.microsoft.com/v1/workspaces' -Headers @{})

        $results.Count | Should -Be 2
        $results[0].id | Should -Be 'w1'
        $results[1].id | Should -Be 'w2'
        $script:pageCalls[1] | Should -Be 'https://api.fabric.microsoft.com/v1/workspaces?continuationToken=token%2F2'
    }
}

Describe 'Get-FabricCapacityName' {
    It 'gets the display name for the configured capacity id' {
        Mock Get-FabricPagedCollection {
            return @(
                [pscustomobject]@{ id = 'other-capacity'; displayName = 'Other' },
                [pscustomobject]@{ id = '33333333-3333-3333-3333-333333333333'; displayName = 'Finance Capacity' }
            )
        }

        $name = Get-FabricCapacityName -CapacityId '33333333-3333-3333-3333-333333333333' -Headers @{}

        $name | Should -Be 'Finance Capacity'
        Assert-MockCalled Get-FabricPagedCollection -ParameterFilter {
            $Uri -eq 'https://api.fabric.microsoft.com/v1/capacities'
        } -Times 1
    }

    It 'fails clearly when the configured capacity is not returned' {
        Mock Get-FabricPagedCollection { return @() }

        $threw = $false
        try {
            Get-FabricCapacityName -CapacityId '33333333-3333-3333-3333-333333333333' -Headers @{}
        }
        catch {
            $threw = $_.Exception.Message -like '*did not return a display name*'
        }

        $threw | Should -Be $true
    }
}

Describe 'Invoke-FabricApiRequest' {
    It 'retries transient transport failures before returning a response' {
        $script:requestAttempts = 0
        Mock Start-Sleep {}
        Mock Invoke-RestMethod {
            $script:requestAttempts++
            if ($script:requestAttempts -eq 1) {
                throw [System.Net.Http.HttpRequestException]::new('The connection was closed by the remote host.')
            }
            return [pscustomobject]@{ value = @([pscustomobject]@{ id = 'policy-rule-1' }) }
        }

        $response = Invoke-FabricApiRequest -Method GET -Uri 'https://api.fabric.microsoft.com/v1/test' -Headers @{}

        $script:requestAttempts | Should -Be 2
        $response.Body.value[0].id | Should -Be 'policy-rule-1'
        Assert-MockCalled Start-Sleep -Times 1
    }
}

Describe 'FPAC environments' {
    It 'limits generated identifiers to safe file-name lengths while retaining their unique suffix' {
        $identifier = ConvertTo-FpacIdentifier -DisplayName ('Policy ' + ('A' * 100)) -Id '12345678-1234-1234-1234-123456789012'

        $identifier.Length | Should -Be 80
        $identifier | Should -Match '-12345678$'
    }

    It 'loads and normalizes tenant and capacity environments' {
        $path = Join-Path $TestDrive 'settings.jsonc'
        Set-Content -LiteralPath $path -Value @'
// FPAC environments support JSONC syntax.
{
  "environments": [
    {
      "name": "Tenant",
      "tenantId": "11111111-1111-1111-1111-111111111111",
      "scope": [{ "type": "Tenant" }]
    },
    {
      "name": "DevCapacity",
      "tenantId": "11111111-1111-1111-1111-111111111111",
      "scope": [
        { "name": "Development One" },
        { "name": "Development Two" }
      ]
    },
  ]
}
'@

        $settings = Get-FpacGlobalSettings -Path $path

        $settings.Environments.Count | Should -Be 2
        $settings.Environments[0].ScopeType | Should -Be 'Tenant'
        $settings.Environments[0].Scopes.Count | Should -Be 1
        $settings.Environments[1].Name | Should -Be 'DevCapacity'
        $settings.Environments[1].CapacityIds.Count | Should -Be 0
        $settings.Environments[1].Scopes[1].Name | Should -Be 'Development Two'
    }

    It 'selects a configured environment case-insensitively' {
        $environments = @(
            [pscustomobject]@{ Name = 'Tenant'; ScopeType = 'Tenant'; Scopes = @([pscustomobject]@{ Type = 'Tenant' }) },
            [pscustomobject]@{ Name = 'DevCapacity'; ScopeType = 'Capacity'; Scopes = @([pscustomobject]@{ Name = 'Development' }) }
        )

        $selected = Select-FpacEnvironment -Environments $environments -EnvironmentName 'devcapacity'

        $selected.Name | Should -Be 'DevCapacity'
    }

    It 'prompts for a numeric environment selection when no name is supplied' {
        $environments = @(
            [pscustomobject]@{ Name = 'Tenant'; ScopeType = 'Tenant'; Scopes = @([pscustomobject]@{ Type = 'Tenant' }) },
            [pscustomobject]@{ Name = 'DevCapacity'; ScopeType = 'Capacity'; Scopes = @([pscustomobject]@{ Name = 'Development' }) }
        )
        Mock Read-Host { return '2' }

        $selected = Select-FpacEnvironment -Environments $environments

        $selected.Name | Should -Be 'DevCapacity'
    }

    It 'requires a capacity name for capacity environments' {
        $path = Join-Path $TestDrive 'invalid-capacity.jsonc'
        Set-Content -LiteralPath $path -Value '{"environments":[{"name":"Capacity","tenantId":"11111111-1111-1111-1111-111111111111","scope":[{}]}]}'

        $threw = $false
        try {
            Get-FpacGlobalSettings -Path $path
        }
        catch {
            $threw = $_.Exception.Message.Contains('scope[].name is required')
        }
        $threw | Should -Be $true
    }

    It 'rejects mixed tenant and capacity scopes in one environment' {
        $path = Join-Path $TestDrive 'mixed-scopes.jsonc'
        Set-Content -LiteralPath $path -Value '{"environments":[{"name":"Mixed","tenantId":"11111111-1111-1111-1111-111111111111","scope":[{"type":"Tenant"},{"name":"Development"}]}]}'

        $threw = $false
        try {
            Get-FpacGlobalSettings -Path $path
        }
        catch {
            $threw = $_.Exception.Message -like '*cannot mix tenant and capacity*'
        }
        $threw | Should -Be $true
    }

    It 'rejects an environment name that is not configured' {
        $environments = @([pscustomobject]@{ Name = 'Tenant'; ScopeType = 'Tenant'; CapacityIds = @() })

        $threw = $false
        try {
            Select-FpacEnvironment -Environments $environments -EnvironmentName 'Missing'
        }
        catch {
            $threw = $_.Exception.Message -like '*not configured*'
        }
        $threw | Should -Be $true
    }
}

Describe 'Get-FabricAuthenticationHeaders' {
    It 'gets a Fabric token from a matching Az.Accounts tenant context' {
        Mock Get-AzContext { return [pscustomobject]@{ Tenant = [pscustomobject]@{ Id = '11111111-1111-1111-1111-111111111111' } } }
        Mock Get-AzAccessToken {
            return [pscustomobject]@{
                Type = 'Bearer'
                Token = ConvertTo-SecureString 'local-test-token' -AsPlainText -Force
            }
        }

        $headers = Get-FabricAuthenticationHeaders -TenantId '11111111-1111-1111-1111-111111111111'

        $headers.Authorization | Should -Be 'Bearer local-test-token'
        Assert-MockCalled Get-AzAccessToken -Times 1
    }

    It 'refuses to authenticate when the Az.Accounts tenant differs from the configured environment' {
        Mock Get-AzContext { return [pscustomobject]@{ Tenant = [pscustomobject]@{ Id = '22222222-2222-2222-2222-222222222222' } } }
        Mock Get-AzAccessToken { throw 'Token should not be requested for the wrong tenant.' }

        $threw = $false
        try {
            Get-FabricAuthenticationHeaders -TenantId '11111111-1111-1111-1111-111111111111'
        }
        catch {
            $threw = $_.Exception.Message -like '*does not match target tenant*'
        }
        $threw | Should -Be $true
    }
}

Describe 'Get-FpacSchemaReference' {
    It 'uses a portable relative reference when the artifact and schema share a root' {
        $artifactDirectory = Join-Path $TestDrive 'output\policyDefinitions'
        $schemaPath = Join-Path $TestDrive 'schemas\policy-definition.schema.json'

        Get-FpacSchemaReference -ArtifactDirectory $artifactDirectory -SchemaPath $schemaPath |
            Should -Be '../../schemas/policy-definition.schema.json'
    }

    It 'uses an absolute file URI when a Windows artifact and schema are on different drives' -Skip:(-not $IsWindows) {
        Get-FpacSchemaReference `
            -ArtifactDirectory 'C:\fpac-output\policyDefinitions' `
            -SchemaPath 'D:\fpac\schemas\policy-definition.schema.json' |
            Should -Be 'file:///D:/fpac/schemas/policy-definition.schema.json'
    }
}
