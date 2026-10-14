function New-FabricPolicySetDefinition {
    param (
        [Parameter(Mandatory)]
        [object] $PolicySet
    )

    $rules = [System.Collections.Generic.List[object]]::new()
    foreach ($policy in @($PolicySet.properties.policies)) {
        $definition = $policy.definition
        $parameters = Get-FabricPropertyValue -InputObject $definition -Name 'parameters'
        $conditions = $definition.conditions |
            ConvertTo-Json -Depth 100 |
            ConvertFrom-Json -Depth 100 -ErrorAction Stop

        foreach ($condition in @($conditions)) {
            if ([string] $condition.type -ne 'Dynamic' -or $null -eq $condition.predicate) {
                continue
            }

            $resolvedValues = [System.Collections.Generic.List[object]]::new()
            foreach ($value in @($condition.predicate.values)) {
                if ($value -is [string] -and $value -match "^\[parameters\('([^']+)'\)\]$") {
                    $parameterName = $Matches[1]
                    $parameter = if ($null -eq $parameters) {
                        $null
                    }
                    else {
                        $parameters.PSObject.Properties[$parameterName]
                    }
                    if ($null -eq $parameter) {
                        throw "Policy '$($policy.name)' references missing parameter '$parameterName'."
                    }
                    foreach ($parameterValue in @($parameter.Value.defaultValue)) {
                        $resolvedValues.Add($parameterValue)
                    }
                }
                else {
                    $resolvedValues.Add($value)
                }
            }
            $condition.predicate.values = @($resolvedValues.ToArray())
        }

        $policyMetadata = Get-FabricPropertyValue -InputObject $policy -Name 'metadata'
        $policyOwner = [string] (Get-FabricPropertyValue -InputObject $policyMetadata -Name 'pacOwnerId')
        $policyId = [string] (Get-FabricPropertyValue -InputObject $policyMetadata -Name 'fpacId')
        $description = [string] (Get-FabricPropertyValue -InputObject $definition -Name 'description')
        if (-not [string]::IsNullOrWhiteSpace($policyOwner) -and -not [string]::IsNullOrWhiteSpace($policyId)) {
            $description = Format-FpacOwnershipDescription -Description $description `
                -PacOwnerId $policyOwner -FpacId $policyId
        }
        $rule = [ordered]@{
            displayName = [string] $definition.displayName
            policy      = [string] $definition.policy
            conditions  = @($conditions)
            effects     = @($definition.effects)
        }
        if (-not [string]::IsNullOrWhiteSpace($description)) {
            $rule['description'] = $description
        }
        $rules.Add($rule)
    }

    $content = [ordered]@{
        '$schema' = 'https://developer.microsoft.com/json-schemas/fabric/item/policySet/definition/1.0.0/schema.json'
        properties = [ordered]@{
            scope = [ordered]@{
                type = [string] $PolicySet.properties.scope.type
            }
        }
        policyRules = @($rules.ToArray())
    }
    $contentJson = $content | ConvertTo-Json -Depth 100 -Compress
    $payload = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($contentJson))

    return [ordered]@{
        format = 'Beta'
        parts  = @(
            [ordered]@{
                path        = 'policySet.json'
                payload     = $payload
                payloadType = 'InlineBase64'
            }
        )
    }
}
