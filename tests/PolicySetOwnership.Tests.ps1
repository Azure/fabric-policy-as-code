BeforeAll {
    . (Join-Path $PSScriptRoot '..\scripts\Deploy\Build-DeploymentPlans.ps1')
}

Describe 'Policy identity without independent ownership' {
    It 'reads ownership metadata from dictionary-backed materialized sets' {
        foreach ($value in @(
            @{ metadata = [pscustomobject]@{ pacOwnerId = 'owner' } }
            [ordered]@{ metadata = [pscustomobject]@{ pacOwnerId = 'owner' } }
            [pscustomobject]@{ metadata = [pscustomobject]@{ pacOwnerId = 'owner' } }
        )) {
            $metadata = Get-FabricPropertyValue -InputObject $value -Name 'metadata'
            Get-FabricPropertyValue -InputObject $metadata -Name 'pacOwnerId' | Should -Be 'owner'
            Get-FabricPropertyValue -InputObject $value -Name 'missing' | Should -BeNullOrEmpty
        }
    }

    It 'exports stable identity without an owner from <Marker>' -ForEach @(
        @{ Marker = '[[FPAC:v1;id=rule-one]]' }
        @{ Marker = '[[FPAC:v1;owner=legacy-owner;id=rule-one]]' }
    ) {
        $rule = [pscustomobject]@{
            id = 'fabric-rule-id'
            displayName = 'Renamed Rule'
            description = "Human text`n`n$Marker"
            policy = 'ItemCreation'
            conditions = @()
            effects = @()
        }
        $artifact = ConvertTo-FpacPolicyDefinition -Rule $rule -SchemaReference '../../schemas/policy-definition.schema.json'
        $artifact.name | Should -Be 'rule-one'
        $artifact.properties.description | Should -Be 'Human text'
        $artifact.Contains('metadata') | Should -BeFalse
        $schema = Join-Path $PSScriptRoot '..\schemas\policy-definition.schema.json'
        Test-Json -Json ($artifact | ConvertTo-Json -Depth 30) -SchemaFile $schema | Should -BeTrue
        $artifact.metadata = @{ pacOwnerId = 'legacy-owner' }
        Test-Json -Json ($artifact | ConvertTo-Json -Depth 30) -SchemaFile $schema | Should -BeTrue
    }

    It 'writes an identity-only marker while preserving human text and replacing legacy ownership' {
        $description = Format-FpacOwnershipDescription -IdentityOnly -FpacId 'rule-one' `
            -Description "Human text`n`n[[FPAC:v1;owner=legacy-owner;id=rule-one]]"
        $description | Should -Be "Human text`n`n[[FPAC:v1;id=rule-one]]"
        Get-FpacHumanDescription -Description $description | Should -Be 'Human text'
        Get-FpacIdentityFromDescription -Description $description | Should -Be 'rule-one'
        Get-FpacOwnershipMetadata -Description $description | Should -BeNullOrEmpty
        Format-FpacOwnershipDescription -IdentityOnly -FpacId 'rule-one' -Description $description |
            Should -Be $description
    }

    It 'still validates marker identity and description length' {
        { Format-FpacOwnershipDescription -IdentityOnly -FpacId 'invalid id' } | Should -Throw '*unsupported marker*'
        { Format-FpacOwnershipDescription -IdentityOnly -FpacId 'rule-one' -MaxLength 5 } | Should -Throw '*character limit*'
    }
}

Describe 'Policy Set ownership boundary' {
    BeforeEach {
        Mock Write-FpacModernSection {}
        Mock Write-FpacModernStatus {}
        $script:rule = [pscustomobject]@{
            name = 'Rule'
            metadata = [pscustomobject]@{ fpacId = 'rule-one' }
            definition = [pscustomobject]@{
                displayName = 'Rule'
                description = 'Human text'
                parameters = [pscustomobject]@{}
                policy = 'ItemCreation'
                conditions = @()
                effects = @()
            }
        }
        $script:set = [pscustomobject]@{
            name = 'set'
            metadata = [pscustomobject]@{ pacOwnerId = 'owner'; fpacId = 'set' }
            properties = [pscustomobject]@{
                workspace = 'Workspace'
                displayName = 'Set'
                scope = [pscustomobject]@{ type = 'Tenant' }
                status = 'Inactive'
                policies = @($script:rule)
            }
        }
        Mock Invoke-FabricApiRequest {
            [pscustomobject]@{ StatusCode = 200; Headers = @{}; Body = $null }
        }
    }

    It 'ignores legacy policy owners without generating policy drift or losing identity' {
        $definitions = @{
            'rule-one' = [pscustomobject]@{
                name = 'rule-one'
                metadata = [pscustomobject]@{ pacOwnerId = 'different-legacy-owner' }
                properties = $script:rule.definition
            }
        }
        $sets = @{
            set = [pscustomobject]@{
                name = 'set'
                metadata = [pscustomobject]@{ pacOwnerId = 'owner' }
                properties = [pscustomobject]@{
                    policies = @([pscustomobject]@{ name = 'rule-one'; parameters = [pscustomobject]@{} })
                }
            }
        }
        $assignments = @{
            assignment = [pscustomobject]@{
                name = 'assignment'
                properties = [pscustomobject]@{
                    policySetName = 'set'; workspace = 'Workspace'; displayName = 'Set'
                    status = 'Inactive'; scope = [pscustomobject]@{ type = 'Tenant' }
                    parameters = [pscustomobject]@{}
                }
            }
        }
        $root = Join-Path $TestDrive 'legacy'
        foreach ($folder in @('policyDefinitions', 'policySetDefinitions', 'policyAssignments')) {
            New-Item -ItemType Directory -Path (Join-Path $root $folder) -Force | Out-Null
        }
        Write-FpacJsonFile -Path (Join-Path $root 'policyDefinitions\rule.json') -Value $definitions['rule-one']
        Write-FpacJsonFile -Path (Join-Path $root 'policySetDefinitions\set.json') -Value $sets.set
        Write-FpacJsonFile -Path (Join-Path $root 'policyAssignments\assignment.json') -Value @{
            '$schema' = '../../schemas/assignment.schema.json'
            name = 'assignment'
            properties = @{
                policySetName = 'set'; displayName = 'Set'; status = 'Inactive'; parameters = @{}
                targets = @{ Test = @(@{ workspace = 'Workspace'; scope = @{ type = 'Tenant' } }) }
            }
        }
        $materialized = New-FpacMaterializedPolicySets -Assignments $assignments `
            -PolicySetDefinitions $sets -PolicyDefinitions $definitions -PacOwnerId 'owner'
        $materialized.Values[0].properties.policies[0].metadata.PSObject.Properties.Name |
            Should -Be @('fpacId')
        $materialized.Values[0].properties.policies[0].metadata.fpacId | Should -Be 'rule-one'
        $plan = New-FpacDeploymentPlan -DesiredRoot $root -DeployedRoot $root -PacOwnerId 'owner' `
            -Target ([pscustomobject]@{
                Name = 'Test'; ScopeType = 'Tenant'
                TenantId = '11111111-1111-1111-1111-111111111111'
                Scopes = @([pscustomobject]@{ Type = 'Tenant'; CapacityId = $null; IncludeCapacities = $false })
            }) -SchemaReference '../../schemas/deployment-plan.schema.json'
        $plan.numberOfChanges | Should -Be 0
        $plan.policySets.numberUnchanged | Should -Be 1
    }

    It 'reconciles every rule in a managed set, regardless of legacy rule owners' {
        Mock Get-FabricPolicyRules {
            @(
                [pscustomobject]@{ id = 'keep'; displayName = 'Old Name'; description = '[[FPAC:v1;owner=other;id=rule-one]]'; policy = 'ItemCreation' }
                [pscustomobject]@{ id = 'plain'; displayName = 'Plain'; description = '' }
                [pscustomobject]@{ id = 'identity'; displayName = 'Identity'; description = '[[FPAC:v1;id=obsolete]]' }
                [pscustomobject]@{ id = 'legacy'; displayName = 'Legacy'; description = '[[FPAC:v1;owner=other;id=obsolete2]]' }
            )
        }
        Set-FabricPolicySetRules -PolicySet $script:set -WorkspaceId 'workspace' -PolicySetId 'set' -Headers @{}
        Should -Invoke Invoke-FabricApiRequest -Times 1 -Exactly -ParameterFilter {
            $Method -eq 'PATCH' -and $Uri -like '*/policyRules/keep?beta=true' -and
            $Body.displayName -eq 'Rule' -and $Body.description -eq "Human text`n`n[[FPAC:v1;id=rule-one]]"
        }
        Should -Invoke Invoke-FabricApiRequest -Times 3 -Exactly -ParameterFilter { $Method -eq 'DELETE' }
        Should -Invoke Invoke-FabricApiRequest -Times 0 -ParameterFilter { $Method -eq 'POST' }
    }

    It 'updates a rule without a marker by display name without a separate adoption flag' {
        Mock Get-FabricPolicyRules {
            @([pscustomobject]@{ id = 'plain'; displayName = 'Rule'; description = ''; policy = 'ItemCreation' })
        }
        Set-FabricPolicySetRules -PolicySet $script:set -WorkspaceId 'workspace' -PolicySetId 'set' -Headers @{}
        Should -Invoke Invoke-FabricApiRequest -Times 1 -Exactly -ParameterFilter {
            $Method -eq 'PATCH' -and $Uri -like '*/policyRules/plain?beta=true'
        }
        Should -Invoke Invoke-FabricApiRequest -Times 0 -ParameterFilter { $Method -in @('POST', 'DELETE') }
    }

    It 'rejects duplicate live rule identities before writing' {
        Mock Get-FabricPolicyRules {
            @(
                [pscustomobject]@{ id = 'one'; displayName = 'One'; description = '[[FPAC:v1;id=rule-one]]' }
                [pscustomobject]@{ id = 'two'; displayName = 'Two'; description = '[[FPAC:v1;owner=legacy;id=rule-one]]' }
            )
        }
        { Set-FabricPolicySetRules -PolicySet $script:set -WorkspaceId 'workspace' -PolicySetId 'set' -Headers @{} } |
            Should -Throw '*More than one live policy rule*'
        Should -Invoke Invoke-FabricApiRequest -Times 0
    }

    It 'writes rule identities during ownership-only set adoption' {
        Mock Set-FabricPolicySetRules {}
        Update-FabricPolicySet -PlanEntry ([pscustomobject]@{
            desired = $script:set; deployed = $script:set; changes = @('ownership')
        }) -ResolvedItem ([pscustomobject]@{ WorkspaceId = 'workspace'; PolicySetId = 'set'; PacOwnerId = '' }) `
            -Headers @{} -PacOwnerId 'owner'
        Should -Invoke Set-FabricPolicySetRules -Times 1 -Exactly
    }

    It 'blocks a different live set owner during planning, adoption and update' {
        $live = $script:set | ConvertTo-Json -Depth 30 | ConvertFrom-Json
        $live.metadata.pacOwnerId = 'other-owner'
        { Build-FpacResourcePlan -ResourceType 'Policy Sets' -Desired @{ set = $script:set } `
            -Deployed @{ set = $live } -PacOwnerId 'owner' } | Should -Throw '*other-owner*'
        $resolved = [pscustomobject]@{
            WorkspaceId = 'workspace'; PolicySetId = 'set'; DisplayName = 'Set'; PacOwnerId = 'other-owner'
        }
        { Set-FabricPolicySetOwnership -PolicySet $script:set -ResolvedItem $resolved -PacOwnerId 'owner' -Headers @{} } |
            Should -Throw '*other-owner*'
        { Update-FabricPolicySet -PlanEntry ([pscustomobject]@{
            desired = $script:set; deployed = $script:set; changes = @('policies')
        }) -ResolvedItem $resolved -PacOwnerId 'owner' -Headers @{} } | Should -Throw '*other-owner*'
        Should -Invoke Invoke-FabricApiRequest -Times 0
    }
}
