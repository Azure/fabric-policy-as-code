BeforeAll {
    . (Join-Path $PSScriptRoot '..\scripts\Deploy\Build-DeploymentPlans.ps1')
}

Describe 'Readable plan change details' {
    BeforeEach {
        Mock Write-FpacModernSection {}
        Mock Write-FpacModernStatus {}
        Mock Write-FpacColoredOutput {}
        $script:capacityMap = @{ TestCapacity = '22222222-2222-2222-2222-222222222222' }
        $script:resource = [pscustomobject]@{
            name = 'internal-resource-id'
            properties = [pscustomobject]@{
                workspace = 'Workspace'
                displayName = 'Set'
                status = 'Active'
            }
        }
    }

    It 'uses workspace and display name for <Action> summaries and detailed headings' -ForEach @(
        @{ Action = 'new'; Label = 'New' }
        @{ Action = 'update'; Label = 'Update' }
        @{ Action = 'replace'; Label = 'Replace' }
        @{ Action = 'adopt'; Label = 'Adopt' }
    ) {
        $plan = New-FpacPlanBucket
        $plan.numberOfChanges = 1
        $plan[$Action].resource = if ($Action -in @('new', 'delete')) { $script:resource } else {
            [pscustomobject]@{
                desired = $script:resource; deployed = $script:resource
                changes = @(); differences = @()
            }
        }

        Write-FpacPlanChangeDetails -ResourceType 'Policy Sets' -ResourcePlan $plan -DetailedOutput

        Should -Invoke Write-FpacModernStatus -Times 1 -Exactly -ParameterFilter {
            $Message -eq "$Label`: Workspace/Set"
        }
        Should -Invoke Write-FpacModernStatus -Times 1 -Exactly -ParameterFilter {
            $Message -eq '[Policy Sets] Detailed Changes for: Workspace/Set'
        }
    }

    It 'shows only a red deletion summary with DetailedOutput=<Detailed>' -ForEach @(
        @{ Detailed = $true }
        @{ Detailed = $false }
    ) {
        $plan = New-FpacPlanBucket
        $plan.numberOfChanges = 1
        $plan.delete.resource = $script:resource
        $before = ConvertTo-FpacCanonicalJson -InputObject $plan

        Write-FpacPlanChangeDetails -ResourceType 'Policy Sets' -ResourcePlan $plan -DetailedOutput:$Detailed

        Should -Invoke Write-FpacModernStatus -Times 1 -Exactly
        Should -Invoke Write-FpacModernStatus -Times 1 -Exactly -ParameterFilter {
            $Message -eq 'Delete: Workspace/Set' -and $Status -eq 'error'
        }
        Should -Invoke Write-FpacColoredOutput -Times 0
        ConvertTo-FpacCanonicalJson -InputObject $plan | Should -Be $before
    }

    It 'does not dump deleted contents when the detailed formatter is called directly' {
        Write-FpacDetailedChanges -ResourceType 'Policy Sets' -Action Delete -Name 'Workspace/Set' -Deployed $script:resource

        Should -Invoke Write-FpacModernStatus -Times 1 -Exactly
        Should -Invoke Write-FpacModernStatus -Times 1 -Exactly -ParameterFilter {
            $Message -eq 'Delete: Workspace/Set' -and $Status -eq 'error'
        }
        Should -Invoke Write-FpacColoredOutput -Times 0
    }

    It 'groups technical paths, prints adoption owner values and resolves scope names without modifying the plan' {
        $differences = @(
            [pscustomobject]@{ path = 'metadata.pacOwnerId'; change = 'Adopt'; oldValue = $null; newValue = 'owner' }
            [pscustomobject]@{ path = 'properties.policies[First].metadata.pacOwnerId'; change = 'Replace'; oldValue = ''; newValue = 'owner' }
            [pscustomobject]@{ path = 'properties.policies[Second].metadata.pacOwnerId'; change = 'Replace'; oldValue = ''; newValue = 'owner' }
            [pscustomobject]@{ path = 'properties.scope.id'; change = 'Add'; oldValue = $null; newValue = $script:capacityMap.TestCapacity }
            [pscustomobject]@{ path = 'properties.status'; change = 'Replace'; oldValue = 'Inactive'; newValue = 'Active' }
        )
        $plan = New-FpacPlanBucket
        $plan.numberOfChanges = 1
        $plan.adopt.resource = [pscustomobject]@{
            desired = $script:resource; deployed = $script:resource
            changes = @('ownership', 'policies', 'scope', 'status'); differences = $differences
        }
        $before = ConvertTo-FpacCanonicalJson -InputObject $plan

        Write-FpacPlanChangeDetails -ResourceType 'Policy Sets' -ResourcePlan $plan `
            -DetailedOutput -CapacityMap $script:capacityMap

        Should -Invoke Write-FpacModernStatus -Times 1 -Exactly -ParameterFilter {
            $Message -eq 'Adopt (Ownership, Policy ownership, Scope, Status): Workspace/Set'
        }
        Should -Invoke Write-FpacModernStatus -Times 1 -Exactly -ParameterFilter {
            $Message -eq "Property: Policy 'First' ownership"
        }
        Should -Invoke Write-FpacColoredOutput -Times 3 -Exactly -ParameterFilter {
            $Message.Trim() -eq '- (unowned)' -and $Color -eq [ConsoleColor]::Red
        }
        Should -Invoke Write-FpacColoredOutput -Times 3 -Exactly -ParameterFilter {
            $Message.Trim() -eq '+ owner' -and $Color -eq [ConsoleColor]::Green
        }
        Should -Invoke Write-FpacColoredOutput -Times 1 -Exactly -ParameterFilter {
            $Message.Trim() -eq '+ Capacity: TestCapacity'
        }
        Should -Invoke Write-FpacColoredOutput -Times 1 -Exactly -ParameterFilter {
            $Message.Trim() -eq '- Inactive'
        }
        Should -Invoke Write-FpacColoredOutput -Times 1 -Exactly -ParameterFilter {
            $Message.Trim() -eq '+ Active'
        }
        ConvertTo-FpacCanonicalJson -InputObject $plan | Should -Be $before
    }

    It 'distinguishes empty strings from missing values' {
        Write-FpacDetailedChanges -ResourceType 'Policy Sets' -Action Update -Name 'Workspace/Set' `
            -Desired $script:resource -Deployed $script:resource -Differences @(
                [pscustomobject]@{ path = 'properties.description'; change = 'Replace'; oldValue = ''; newValue = 'Text' }
            )
        Should -Invoke Write-FpacColoredOutput -Times 1 -Exactly -ParameterFilter {
            $Message.Trim() -eq '- ""'
        }
    }
}

Describe 'Readable scope and property labels' {
    It 'resolves <Scope> to <Expected>' -ForEach @(
        @{ Scope = 'Tenant'; Expected = 'Tenant' }
        @{ Scope = 'Capacity:22222222-2222-2222-2222-222222222222'; Expected = 'Capacity: TestCapacity' }
        @{ Scope = 'Capacity:Unbound'; Expected = 'Capacity (unassigned)' }
        @{ Scope = 'Capacity:unknown'; Expected = 'Capacity: unknown (name unavailable)' }
    ) {
        Format-FpacScopeDisplayName -ScopeKey $Scope `
            -CapacityMap @{ TestCapacity = '22222222-2222-2222-2222-222222222222' } |
            Should -Be $Expected
    }

    It 'retains the specific policy and changed field for parameter differences' {
        Format-FpacPlanPropertyPath -Path 'properties.policies[Rule].definition.parameters.condition1Values.defaultValue[]' |
            Should -Be "Policy 'Rule': parameters.condition1Values.defaultValue[]"
        Format-FpacPlanPropertyPath -Path 'properties.policies[Rule].definition.parameters.condition1Values.defaultValue[]' -Summary |
            Should -Be 'Policies'
    }
}
