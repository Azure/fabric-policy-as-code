function Get-ResponseHeaderValue {
    param (
        [Parameter()]
        [object] $Headers,

        [Parameter(Mandatory)]
        [string] $Name
    )

    if ($null -eq $Headers) {
        return $null
    }

    foreach ($key in $Headers.Keys) {
        if ([string]::Equals([string] $key, $Name, [System.StringComparison]::OrdinalIgnoreCase)) {
            $value = $Headers[$key]
            if ($value -is [array]) {
                return [string] $value[0]
            }
            return [string] $value
        }
    }

    return $null
}
