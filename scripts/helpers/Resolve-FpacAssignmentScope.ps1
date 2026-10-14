function Resolve-FpacAssignmentScope {
    param (
        [Parameter(Mandatory)]
        [object] $Scope,

        [Parameter(Mandatory)]
        [System.Collections.IDictionary] $CapacityMap
    )

    $scopeType = [string] (Get-FabricPropertyValue -InputObject $Scope -Name 'type')
    if ([string]::IsNullOrWhiteSpace($scopeType)) {
        $scopeType = 'Capacity'
    }
    if ($scopeType -eq 'Tenant') {
        return [pscustomobject]@{
            type = 'Tenant'
            id = $null
        }
    }
    if ($scopeType -ne 'Capacity') {
        throw "Assignment scope type '$scopeType' is not supported."
    }

    $name = [string] (Get-FabricPropertyValue -InputObject $Scope -Name 'name')
    $id = [string] (Get-FabricPropertyValue -InputObject $Scope -Name 'id')
    if ([string]::IsNullOrWhiteSpace($id)) {
        if ([string]::IsNullOrWhiteSpace($name)) {
            return [pscustomobject]@{
                type = 'Capacity'
                id = $null
            }
        }
        if (-not $CapacityMap.Contains($name)) {
            throw "Capacity '$name' was not returned by Fabric and is not configured in global settings."
        }
        $id = [string] $CapacityMap[$name]
    }
    elseif (-not [string]::IsNullOrWhiteSpace($name) -and
        $CapacityMap.Contains($name) -and
        -not [string]::Equals([string] $CapacityMap[$name], $id, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Capacity scope '$name' specifies id '$id', but the resolved id is '$($CapacityMap[$name])'."
    }

    return [pscustomobject]@{
        type = 'Capacity'
        id = $id
    }
}
