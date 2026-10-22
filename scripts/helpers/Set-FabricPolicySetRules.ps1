function Set-FabricPolicySetRules {
    param (
        [Parameter(Mandatory)]
        [object] $PolicySet,

        [Parameter(Mandatory)]
        [string] $WorkspaceId,

        [Parameter(Mandatory)]
        [string] $PolicySetId,

        [Parameter(Mandatory)]
        [hashtable] $Headers,

        [Parameter()]
        [ValidateRange(1, 7200)]
        [int] $OperationTimeoutSeconds = 1800
    )

    $definition = New-FabricPolicySetDefinition -PolicySet $PolicySet
    $content = [Text.Encoding]::UTF8.GetString(
        [Convert]::FromBase64String([string] $definition.parts[0].payload)
    ) | ConvertFrom-Json -Depth 100 -ErrorAction Stop
    $desiredRules = @($content.policyRules)
    $deployedRules = @(Get-FabricPolicyRules -WorkspaceId $WorkspaceId -PolicySetId $PolicySetId -Headers $Headers)
    $matchedRuleIds = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    $workspaceName = [string] (Get-FabricPropertyValue -InputObject $PolicySet.properties -Name 'workspace')
    if ([string]::IsNullOrWhiteSpace($workspaceName)) { $workspaceName = $WorkspaceId }
    $resourceLabel = "$workspaceName/$([string] (Get-FabricPropertyValue -InputObject $PolicySet.properties -Name 'displayName'))"

    foreach ($desiredRule in $desiredRules) {
        $desiredRuleDescription = [string] (Get-FabricPropertyValue -InputObject $desiredRule -Name 'description')
        $desiredId = Get-FpacIdentityFromDescription -Description $desiredRuleDescription
        if ([string]::IsNullOrWhiteSpace($desiredId)) {
            throw "Desired policy rule '$($desiredRule.displayName)' does not contain an FPAC identity."
        }
        $matchingRules = @($deployedRules | Where-Object {
            $identity = Get-FpacIdentityFromDescription -Description ([string] $_.description)
            [string]::Equals($identity, $desiredId, [System.StringComparison]::OrdinalIgnoreCase)
        })
        if ($matchingRules.Count -gt 1) {
            throw "More than one live policy rule has FPAC id '$desiredId'."
        }

        $matchingRule = if ($matchingRules.Count -eq 1) {
            $matchingRules[0]
        }
        else {
            $displayMatches = @($deployedRules | Where-Object {
                [string]::Equals([string] $_.displayName, [string] $desiredRule.displayName, [System.StringComparison]::OrdinalIgnoreCase)
            })
            if ($displayMatches.Count -gt 1) {
                throw "More than one live policy rule is named '$($desiredRule.displayName)'."
            }
            if ($displayMatches.Count -eq 1) {
                $displayMatches[0]
            }
        }

        $createBody = [ordered]@{
            displayName = [string] $desiredRule.displayName
            description = $desiredRuleDescription
            policy      = [string] $desiredRule.policy
            conditions  = @($desiredRule.conditions)
            effects     = @($desiredRule.effects)
        }
        if ($null -eq $matchingRule) {
            $uri = "$script:FabricApiBaseUri/workspaces/$WorkspaceId/policySets/$PolicySetId/policyRules?beta=true"
            $response = Invoke-FabricApiRequest -Method POST -Uri $uri -Headers $Headers -Body $createBody
            if ($response.StatusCode -notin @(201, 202)) {
                throw "Fabric policy rule creation for '$($desiredRule.displayName)' returned HTTP $($response.StatusCode)."
            }
            $null = Wait-FabricLongRunningOperation -Response $response -Headers $Headers `
                -TimeoutSeconds $OperationTimeoutSeconds
            Write-FpacModernStatus -Message "Created policy: $resourceLabel/$($desiredRule.displayName)" -Status success -Indent 4
            continue
        }

        $ruleId = [string] $matchingRule.id
        $null = $matchedRuleIds.Add($ruleId)
        if (-not [string]::Equals([string] $matchingRule.policy, [string] $desiredRule.policy, [System.StringComparison]::OrdinalIgnoreCase)) {
            $deleteUri = "$script:FabricApiBaseUri/workspaces/$WorkspaceId/policySets/$PolicySetId/policyRules/$($ruleId)?beta=true"
            $deleteResponse = Invoke-FabricApiRequest -Method DELETE -Uri $deleteUri -Headers $Headers
            if ($deleteResponse.StatusCode -ne 200) {
                throw "Fabric policy rule deletion for '$ruleId' returned HTTP $($deleteResponse.StatusCode)."
            }
            Write-FpacModernStatus -Message "Deleted policy: $resourceLabel/$($matchingRule.displayName) (policy type changed)" -Status error -Indent 4
            $createUri = "$script:FabricApiBaseUri/workspaces/$WorkspaceId/policySets/$PolicySetId/policyRules?beta=true"
            $createResponse = Invoke-FabricApiRequest -Method POST -Uri $createUri -Headers $Headers -Body $createBody
            if ($createResponse.StatusCode -notin @(201, 202)) {
                throw "Fabric policy rule recreation for '$($desiredRule.displayName)' returned HTTP $($createResponse.StatusCode)."
            }
            $null = Wait-FabricLongRunningOperation -Response $createResponse -Headers $Headers `
                -TimeoutSeconds $OperationTimeoutSeconds
            Write-FpacModernStatus -Message "Created policy: $resourceLabel/$($desiredRule.displayName)" -Status success -Indent 4
            continue
        }

        $updateUri = "$script:FabricApiBaseUri/workspaces/$WorkspaceId/policySets/$PolicySetId/policyRules/$($ruleId)?beta=true"
        $updateResponse = Invoke-FabricApiRequest -Method PATCH -Uri $updateUri -Headers $Headers -Body ([ordered]@{
            displayName = [string] $desiredRule.displayName
            description = [string] $desiredRule.description
            conditions  = @($desiredRule.conditions)
        })
        if ($updateResponse.StatusCode -ne 200) {
            throw "Fabric policy rule update for '$ruleId' returned HTTP $($updateResponse.StatusCode)."
        }
        if ([string] $matchingRule.displayName -ne [string] $desiredRule.displayName) {
            Write-FpacModernStatus -Message "Renamed policy: $resourceLabel/$($matchingRule.displayName) -> $($desiredRule.displayName)" -Status update -Indent 4
        }
        else {
            Write-FpacModernStatus -Message "Updated policy: $resourceLabel/$($desiredRule.displayName)" -Status update -Indent 4
        }
    }

    foreach ($deployedRule in $deployedRules) {
        $ruleId = [string] $deployedRule.id
        if ($matchedRuleIds.Contains($ruleId)) {
            continue
        }
        $uri = "$script:FabricApiBaseUri/workspaces/$WorkspaceId/policySets/$PolicySetId/policyRules/$($ruleId)?beta=true"
        $response = Invoke-FabricApiRequest -Method DELETE -Uri $uri -Headers $Headers
        if ($response.StatusCode -ne 200) {
            throw "Fabric policy rule deletion for '$ruleId' returned HTTP $($response.StatusCode)."
        }
        Write-FpacModernStatus -Message "Deleted policy: $resourceLabel/$($deployedRule.displayName)" -Status error -Indent 4
    }
}
