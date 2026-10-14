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
        [string] $PacOwnerId,

        [Parameter()]
        [ValidateSet('OwnedOnly', 'Full')]
        [string] $DesiredStateStrategy = 'OwnedOnly',

        [Parameter()]
        [switch] $AdoptUnowned,

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

    foreach ($desiredRule in $desiredRules) {
        $desiredRuleDescription = [string] (Get-FabricPropertyValue -InputObject $desiredRule -Name 'description')
        $desiredOwnership = Get-FpacOwnershipMetadata -Description $desiredRuleDescription
        if ($null -eq $desiredOwnership) {
            throw "Desired policy rule '$($desiredRule.displayName)' does not contain FPAC ownership metadata."
        }
        $matchingRules = @($deployedRules | Where-Object {
            $ownership = Get-FpacOwnershipMetadata -Description ([string] $_.description)
            $null -ne $ownership -and
            [string]::Equals($ownership.PacOwnerId, $desiredOwnership.PacOwnerId, [System.StringComparison]::OrdinalIgnoreCase) -and
            [string]::Equals($ownership.FpacId, $desiredOwnership.FpacId, [System.StringComparison]::OrdinalIgnoreCase)
        })
        if ($matchingRules.Count -gt 1) {
            throw "More than one live policy rule has FPAC id '$($desiredOwnership.FpacId)'."
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
                $existingOwnership = Get-FpacOwnershipMetadata -Description ([string] $displayMatches[0].description)
                if ($null -ne $existingOwnership -and
                    -not [string]::Equals($existingOwnership.PacOwnerId, $PacOwnerId, [System.StringComparison]::OrdinalIgnoreCase)) {
                    throw "Policy rule '$($desiredRule.displayName)' is owned by '$($existingOwnership.PacOwnerId)' and cannot be adopted by '$PacOwnerId'."
                }
                if ($null -eq $existingOwnership -and -not $AdoptUnowned) {
                    throw "Policy rule '$($desiredRule.displayName)' is unowned. Rerun an adoption plan with -AdoptUnowned."
                }
                $matchingRule = $displayMatches[0]
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
            $createUri = "$script:FabricApiBaseUri/workspaces/$WorkspaceId/policySets/$PolicySetId/policyRules?beta=true"
            $createResponse = Invoke-FabricApiRequest -Method POST -Uri $createUri -Headers $Headers -Body $createBody
            if ($createResponse.StatusCode -notin @(201, 202)) {
                throw "Fabric policy rule recreation for '$($desiredRule.displayName)' returned HTTP $($createResponse.StatusCode)."
            }
            $null = Wait-FabricLongRunningOperation -Response $createResponse -Headers $Headers `
                -TimeoutSeconds $OperationTimeoutSeconds
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
    }

    foreach ($deployedRule in $deployedRules) {
        $ruleId = [string] $deployedRule.id
        if ($matchedRuleIds.Contains($ruleId)) {
            continue
        }
        $ownership = Get-FpacOwnershipMetadata -Description ([string] $deployedRule.description)
        $isOwned = $null -ne $ownership -and
            [string]::Equals($ownership.PacOwnerId, $PacOwnerId, [System.StringComparison]::OrdinalIgnoreCase)
        if (-not $isOwned -and $DesiredStateStrategy -eq 'OwnedOnly') {
            continue
        }
        $uri = "$script:FabricApiBaseUri/workspaces/$WorkspaceId/policySets/$PolicySetId/policyRules/$($ruleId)?beta=true"
        $response = Invoke-FabricApiRequest -Method DELETE -Uri $uri -Headers $Headers
        if ($response.StatusCode -ne 200) {
            throw "Fabric policy rule deletion for '$ruleId' returned HTTP $($response.StatusCode)."
        }
    }
}
