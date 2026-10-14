function Get-FpacCapacityMap {
    param (
        [Parameter(Mandatory)]
        [hashtable] $Headers
    )

    $capacityMap = [System.Collections.Hashtable]::new([System.StringComparer]::OrdinalIgnoreCase)
    $capacities = @(Get-FabricPagedCollection -Uri "$script:FabricApiBaseUri/capacities" -Headers $Headers)
    foreach ($capacity in $capacities) {
        $name = [string] $capacity.displayName
        $id = [string] $capacity.id
        if ([string]::IsNullOrWhiteSpace($name) -or [string]::IsNullOrWhiteSpace($id)) {
            throw 'Fabric returned a capacity without both displayName and id.'
        }
        if ($capacityMap.ContainsKey($name)) {
            throw "Fabric returned more than one accessible capacity named '$name'. FPAC environment capacity names must be unique."
        }
        $capacityMap[$name] = $id
    }

    return $capacityMap
}
