BeforeAll {
    . (Join-Path $PSScriptRoot '..\scripts\Deploy\Deploy-Policy.ps1')
}

Describe 'Deployment operation details' {
    BeforeEach {
        Mock Write-FpacModernStatus {}
        Mock Invoke-FabricApiRequest {
            $status = if ($Method -eq 'POST' -and $Uri -like '*policyRules?beta=true') { 201 } else { 200 }
            [pscustomobject]@{ StatusCode = $status; Headers = @{}; Body = $null }
        }
        Mock Wait-FabricLongRunningOperation { [pscustomobject]@{ id = 'new-set-id' } }
        $script:rule = [pscustomobject]@{
            name = 'Rule'
            metadata = [pscustomobject]@{ fpacId = 'rule-id' }
            definition = [pscustomobject]@{
                displayName = 'Rule'; description = 'Human text'; parameters = [pscustomobject]@{}
                policy = 'ItemCreation'; conditions = @(); effects = @()
            }
        }
        $script:set = [pscustomobject]@{
            name = 'set'
            metadata = [pscustomobject]@{ pacOwnerId = 'owner'; fpacId = 'set' }
            properties = [pscustomobject]@{
                workspace = 'Workspace'; displayName = 'Set'; description = 'New description'
                scope = [pscustomobject]@{ type = 'Tenant' }; status = 'Inactive'
                policies = @($script:rule)
            }
        }
        $script:resolved = [pscustomobject]@{
            WorkspaceId = 'workspace-id'; WorkspaceName = 'Workspace'
            PolicySetId = 'set-id'; DisplayName = 'Set'; PacOwnerId = 'owner'
        }
        Mock Get-FabricPolicyRules {
            @(
                [pscustomobject]@{ id = 'rule'; displayName = 'Rule'; description = '[[FPAC:v1;id=rule-id]]'; policy = 'ItemCreation' }
                [pscustomobject]@{ id = 'obsolete'; displayName = 'Obsolete'; description = ''; policy = 'ItemCreation' }
            )
        }
    }

    It 'reports completed rule updates and deletions by name' {
        Set-FabricPolicySetRules -PolicySet $script:set -WorkspaceId 'workspace-id' -PolicySetId 'set-id' -Headers @{}
        Should -Invoke Write-FpacModernStatus -Times 1 -Exactly -ParameterFilter {
            $Message -eq 'Updated policy: Rule' -and $Indent -eq 4
        }
        Should -Invoke Write-FpacModernStatus -Times 1 -Exactly -ParameterFilter {
            $Message -eq 'Deleted policy: Obsolete' -and $Status -eq 'error' -and $Indent -eq 4
        }
    }

    It 'reports individual rule creation after the operation completes' {
        Mock Get-FabricPolicyRules { @() }
        Set-FabricPolicySetRules -PolicySet $script:set -WorkspaceId 'workspace-id' -PolicySetId 'set-id' -Headers @{}
        Should -Invoke Write-FpacModernStatus -Times 1 -Exactly -ParameterFilter {
            $Message -eq 'Created policy: Rule' -and $Status -eq 'success' -and $Indent -eq 4
        }
        Should -Invoke Wait-FabricLongRunningOperation -Times 1 -Exactly
    }

    It 'reports set creation and included rules without claiming an activation for an inactive set' {
        $script:creationMessages = [System.Collections.Generic.List[string]]::new()
        Mock Write-FpacModernStatus { $script:creationMessages.Add($Message) }
        Mock Invoke-FabricApiRequest { [pscustomobject]@{ StatusCode = 201; Headers = @{}; Body = $null } }
        $id = New-FabricPolicySet -PolicySet $script:set -WorkspaceId 'workspace-id' -Headers @{}
        $id | Should -Be 'new-set-id'
        Should -Invoke Write-FpacModernStatus -Times 1 -Exactly -ParameterFilter { $Message -eq 'Created: Workspace/Set' }
        Should -Invoke Write-FpacModernStatus -Times 1 -Exactly -ParameterFilter { $Message -eq 'Created policy: Rule' -and $Indent -eq 4 }
        Should -Invoke Write-FpacModernStatus -Times 0 -ParameterFilter { $Message -like '*Activation accepted*' }
        $script:creationMessages[0] | Should -Be 'Created: Workspace/Set'
        $script:creationMessages[1] | Should -Be 'Created policy: Rule'
    }

    It 'reports ownership after a successful write' {
        Set-FabricPolicySetOwnership -PolicySet $script:set -ResolvedItem $script:resolved -Headers @{} -PacOwnerId 'owner'
        Should -Invoke Write-FpacModernStatus -Times 1 -Exactly -ParameterFilter {
            $Message -eq 'Assigned owner: owner' -and $Indent -eq 4
        }
    }

    It 'reports metadata changes and accepted capacity transitions with resolved names' {
        $old = $script:set | ConvertTo-Json -Depth 30 | ConvertFrom-Json
        $old.properties.status = 'Active'
        $old.properties.scope = [pscustomobject]@{ type = 'Capacity'; id = 'old-capacity' }
        $old.properties.displayName = 'Old Set'
        $script:set.properties.status = 'Active'
        $script:set.properties.scope = [pscustomobject]@{ type = 'Capacity'; id = 'new-capacity' }
        Update-FabricPolicySet -PlanEntry ([pscustomobject]@{
            desired = $script:set; deployed = $old; changes = @('displayName', 'description', 'scope')
        }) -ResolvedItem $script:resolved -Headers @{} -PacOwnerId 'owner' `
            -CapacityMap @{ OldCapacity = 'old-capacity'; NewCapacity = 'new-capacity' }

        Should -Invoke Write-FpacModernStatus -Times 1 -Exactly -ParameterFilter {
            $Message -eq 'Renamed: Old Set -> Set' -and $Indent -eq 4
        }
        Should -Invoke Write-FpacModernStatus -Times 1 -Exactly -ParameterFilter {
            $Message -eq 'Updated description' -and $Indent -eq 4
        }
        Should -Invoke Write-FpacModernStatus -Times 1 -Exactly -ParameterFilter {
            $Message -like 'Deactivation accepted: Workspace/Set on Capacity: OldCapacity*' -and $Status -eq 'error'
        }
        Should -Invoke Write-FpacModernStatus -Times 1 -Exactly -ParameterFilter {
            $Message -like 'Activation accepted: Workspace/Set on Capacity: NewCapacity*' -and $Status -eq 'success'
        }
    }

    It 'never reports a failed rule write as completed' {
        Mock Invoke-FabricApiRequest { [pscustomobject]@{ StatusCode = 500; Headers = @{}; Body = $null } }
        { Set-FabricPolicySetRules -PolicySet $script:set -WorkspaceId 'workspace-id' -PolicySetId 'set-id' -Headers @{} } |
            Should -Throw '*HTTP 500*'
        Should -Invoke Write-FpacModernStatus -Times 0
    }

    It 'never reports a failed activation as accepted' {
        Mock Invoke-FabricApiRequest { [pscustomobject]@{ StatusCode = 500; Headers = @{}; Body = $null } }
        { Set-FabricPolicySetStatus -WorkspaceId 'workspace-id' -PolicySetId 'set-id' -Scope $script:set.properties.scope `
            -Headers @{} -CurrentStatus Inactive -DesiredStatus Active -ResourceLabel 'Workspace/Set' } |
            Should -Throw '*HTTP 500*'
        Should -Invoke Write-FpacModernStatus -Times 0
    }
}

Describe 'Deployment result and preview output' {
    BeforeEach {
        Mock Write-FpacModernHeader {}
        Mock Write-FpacModernSection {}
        Mock Write-FpacModernStatus {}
        Mock Get-FabricAuthenticationHeaders { @{} }
        Mock Get-FpacCapacityMap { @{} }
        Mock New-FabricPolicySet { 'new-id' }
        Mock Update-FabricPolicySet {}
        Mock Remove-FabricPolicySet {}
        Mock Set-FabricPolicySetOwnership {}
        $script:settingsPath = Join-Path $TestDrive 'output-settings.json'
        Write-FpacJsonFile -Path $script:settingsPath -Value @{
            pacOwnerId = 'owner'
            environments = @(@{
                name = 'Tenant'; tenantId = '11111111-1111-1111-1111-111111111111'
                scope = @(@{ type = 'Tenant'; includeCapacities = $false })
            })
        }
        $script:bucket = New-FpacPlanBucket
        $script:bucket.numberOfChanges = 5
        $liveSets = @{}
        foreach ($action in @('new', 'update', 'replace', 'adopt', 'delete')) {
            $resource = @{
                name = $action
                properties = @{
                    workspace = 'Workspace'; displayName = $action; status = 'Inactive'
                    scope = @{ type = 'Tenant' }; policies = @()
                }
            }
            if ($action -in @('new', 'delete')) {
                $script:bucket[$action][$action] = $resource
            }
            else {
                $script:bucket[$action][$action] = @{
                    name = $action; desired = $resource; deployed = $resource
                    changes = @('description'); differences = @()
                }
            }
            if ($action -ne 'new') {
                $liveSets[$action] = [pscustomobject]@{
                    Id = "$action-id"; DisplayName = $action; PacOwnerId = 'owner'
                }
            }
        }
        $script:inventory = @{ Workspace = [pscustomobject]@{ Id = 'workspace-id'; Name = 'Workspace'; PolicySets = $liveSets } }
        Mock Get-FpacDeploymentInventory { $script:inventory }
        $script:planPath = Join-Path $TestDrive 'output-plan.json'
        Write-FpacJsonFile -Path $script:planPath -Value @{
            '$schema' = '../../schemas/deployment-plan.schema.json'; createdOn = '2026-10-22 12:00:00Z'
            pacOwnerId = 'owner'; desiredStateStrategy = 'OwnedOnly'
            environment = @{
                name = 'Tenant'; tenantId = '11111111-1111-1111-1111-111111111111'
                scopes = @(@{ type = 'Tenant'; capacityId = $null; includeCapacities = $false })
            }
            policySets = $script:bucket; activationChanges = @(); numberOfChanges = 5; numberUnchanged = 0
        }
        $script:arguments = @{
            PlanFile = $script:planPath; GlobalSettingsPath = $script:settingsPath
            SchemaPath = Join-Path $PSScriptRoot '..\schemas\deployment-plan.schema.json'
            MaxRetryAttempts = 1; AdoptUnowned = $true; Confirm = $false
        }
    }

    It 'labels WhatIf as a preview and never reports completed actions or calls write helpers' {
        $result = Invoke-FpacDeployPolicyOperation @script:arguments -WhatIf
        $result.Skipped | Should -Be 5
        $result.Created + $result.Updated + $result.Replaced + $result.Adopted + $result.Deleted | Should -Be 0
        Should -Invoke New-FabricPolicySet -Times 0
        Should -Invoke Update-FabricPolicySet -Times 0
        Should -Invoke Remove-FabricPolicySet -Times 0
        Should -Invoke Set-FabricPolicySetOwnership -Times 0
        Should -Invoke Write-FpacModernHeader -Times 1 -Exactly -ParameterFilter {
            $Title -eq 'FPAC Deployment Preview Complete' -and $Subtitle -eq 'No Fabric changes were applied'
        }
        Should -Invoke Write-FpacModernStatus -Times 5 -Exactly -ParameterFilter { $Message -like 'Would *: Workspace/*' }
        Should -Invoke Write-FpacModernStatus -Times 0 -ParameterFilter {
            $Message -match '^(Created|Updated|Replaced|Adopted|Deleted):' -or $Message -like '*Activation*accepted*'
        }
    }

    It 'places the <Operation> set heading before indented policy results without a trailing set-updated line' -ForEach @(
        @{ Operation = 'update' }
        @{ Operation = 'adopt' }
    ) {
        $plan = Get-Content -LiteralPath $script:planPath -Raw | ConvertFrom-Json -Depth 100
        $entry = $plan.policySets.$Operation.$Operation
        $entry.changes = if ($Operation -eq 'adopt') { @('ownership', 'policies') } else { @('policies') }
        $bucket = New-FpacPlanBucket
        $bucket.numberOfChanges = 1
        $bucket[$Operation][$Operation] = $entry
        $plan.policySets = $bucket
        $plan.numberOfChanges = 1
        Write-FpacJsonFile -Path $script:planPath -Value $plan
        $script:messages = [System.Collections.Generic.List[object]]::new()
        Mock Write-FpacModernStatus {
            $script:messages.Add([pscustomobject]@{ Message = $Message; Indent = $Indent; Status = $Status })
        }
        Mock Update-FabricPolicySet {
            Write-FpacModernStatus -Message 'Updated policy: Rule' -Status update -Indent 4
        }
        Mock Set-FabricPolicySetOwnership {
            Write-FpacModernStatus -Message 'Assigned owner: owner' -Status success -Indent 4
        }

        $result = Invoke-FpacDeployPolicyOperation @script:arguments

        $result.Skipped | Should -Be 0
        $headingIndex = [Array]::IndexOf([object[]] $script:messages.Message, "Policy Set: Workspace/$Operation")
        $policyIndex = [Array]::IndexOf([object[]] $script:messages.Message, 'Updated policy: Rule')
        $headingIndex | Should -BeGreaterOrEqual 0
        $policyIndex | Should -BeGreaterThan $headingIndex
        $script:messages[$headingIndex].Indent | Should -Be 2
        $script:messages[$headingIndex].Status | Should -Be 'info'
        $script:messages[$policyIndex].Indent | Should -Be 4
        if ($Operation -eq 'adopt') {
            $ownerIndex = [Array]::IndexOf([object[]] $script:messages.Message, 'Assigned owner: owner')
            $ownerIndex | Should -BeGreaterThan $headingIndex
            $ownerIndex | Should -BeLessThan $policyIndex
        }
        Should -Invoke Write-FpacModernStatus -Times 0 -ParameterFilter {
            $Message -like 'Updated: Workspace/*' -or $Message -like 'Adopted: Workspace/*'
        }
    }

    It 'summarizes successful writes without claiming an activation for inactive sets' {
        $result = Invoke-FpacDeployPolicyOperation @script:arguments
        $result.Created | Should -Be 1
        $result.Updated | Should -Be 1
        $result.Replaced | Should -Be 1
        $result.Adopted | Should -Be 1
        $result.Deleted | Should -Be 1
        $result.Skipped | Should -Be 0
        Should -Invoke Write-FpacModernStatus -Times 5 -Exactly -ParameterFilter {
            $Message -match '^(Created|Updated|Replaced|Adopted|Deleted): 1$'
        }
        Should -Invoke Write-FpacModernStatus -Times 0 -ParameterFilter {
            $Message -like '*Activation*accepted*' -or $Message -eq 'Skipped: 0'
        }
    }
}
