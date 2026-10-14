function Get-FabricCapacityName {
    param (
        [Parameter(Mandatory)]
        [string] $CapacityId,

        [Parameter(Mandatory)]
        [hashtable] $Headers
    )

    $capacities = @(Get-FabricPagedCollection -Uri "$script:FabricApiBaseUri/capacities" -Headers $Headers)
    $capacity = $capacities | Where-Object {
        [string]::Equals([string] $_.id, $CapacityId, [System.StringComparison]::OrdinalIgnoreCase)
    } | Select-Object -First 1
    if ($null -eq $capacity -or [string]::IsNullOrWhiteSpace([string] $capacity.displayName)) {
        throw "Fabric did not return a display name for configured capacity '$CapacityId'."
    }

    return [string] $capacity.displayName
}
