function ConvertTo-FpacPolicyDefinition {
    param (
        [Parameter(Mandatory)]
        [object] $Rule,

        [Parameter(Mandatory)]
        [string] $SchemaReference
    )

    if ([string]::IsNullOrWhiteSpace([string] $Rule.displayName)) {
        throw 'Fabric returned a policy rule without displayName.'
    }
    if ([string]::IsNullOrWhiteSpace([string] $Rule.policy)) {
        throw "Fabric policy rule '$($Rule.displayName)' is missing its policy type."
    }

    $parameters = [ordered]@{}
    $conditions = [System.Collections.Generic.List[object]]::new()
    $conditionNumber = 0
    foreach ($condition in @($Rule.conditions)) {
        $conditionNumber++
        $conditionCopy = $condition | ConvertTo-Json -Depth 30 | ConvertFrom-Json -ErrorAction Stop
        if ([string] $conditionCopy.type -eq 'Dynamic' -and
            $null -ne $conditionCopy.predicate -and
            $null -ne $conditionCopy.predicate.values) {
            $parameterName = "condition${conditionNumber}Values"
            $parameters[$parameterName] = [ordered]@{
                type         = 'Array'
                defaultValue = @($conditionCopy.predicate.values)
                metadata     = [ordered]@{
                    displayName  = "Condition $conditionNumber values"
                    targetProperty = [string] $conditionCopy.targetProperty
                }
            }
            $conditionCopy.predicate.values = @("[parameters('$parameterName')]")
        }
        $conditions.Add($conditionCopy)
    }

    $ownership = Get-FpacOwnershipMetadata -Description ([string] $Rule.description)
    $humanDescription = Get-FpacHumanDescription -Description ([string] $Rule.description)
    $properties = [ordered]@{
        displayName = [string] $Rule.displayName
        parameters  = $parameters
        policy      = [string] $Rule.policy
        conditions  = @($conditions.ToArray())
        effects     = @($Rule.effects)
    }
    if (-not [string]::IsNullOrWhiteSpace($humanDescription)) {
        $properties['description'] = $humanDescription
    }

    $artifact = [ordered]@{
        '$schema'   = $SchemaReference
        name        = if ($null -ne $ownership) {
            $ownership.FpacId
        }
        else {
            ConvertTo-FpacIdentifier -DisplayName ([string] $Rule.displayName) -Id ([string] $Rule.id)
        }
        properties  = $properties
    }
    if ($null -ne $ownership) {
        $artifact['metadata'] = [ordered]@{
            pacOwnerId = $ownership.PacOwnerId
        }
    }
    return $artifact
}
