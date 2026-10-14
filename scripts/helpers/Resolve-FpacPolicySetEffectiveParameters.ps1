function Resolve-FpacPolicySetEffectiveParameters {
    param (
        [Parameter(Mandatory)]
        [object] $PolicySet,

        [Parameter(Mandatory)]
        [System.Collections.IDictionary] $PolicyDefinitions
    )

    $resolved = $PolicySet | ConvertTo-Json -Depth 100 | ConvertFrom-Json -ErrorAction Stop
    foreach ($policyReference in @($resolved.properties.policies)) {
        $definitionName = [string] $policyReference.name
        if (-not $PolicyDefinitions.Contains($definitionName)) {
            continue
        }

        $definition = $PolicyDefinitions[$definitionName]
        $effectiveParameters = [ordered]@{}
        foreach ($parameter in @($definition.properties.parameters.PSObject.Properties) | Sort-Object Name) {
            $override = $policyReference.parameters.PSObject.Properties[$parameter.Name]
            $value = if ($null -ne $override -and $null -ne $override.Value.PSObject.Properties['value']) {
                $override.Value.value
            }
            else {
                throw "Policy definition '$definitionName' requires parameter '$($parameter.Name)', but the deployment assignment did not supply a value."
            }
            if ([string] $parameter.Value.type -eq 'Array') {
                $value = @($value)
            }
            $effectiveParameters[$parameter.Name] = [ordered]@{ value = $value }
        }
        $policyReference.parameters = [pscustomobject] $effectiveParameters
    }
    $resolved.properties.policies = @($resolved.properties.policies)
    return $resolved
}
