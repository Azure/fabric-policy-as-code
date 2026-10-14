function ConvertTo-FpacIdentifier {
    param (
        [Parameter(Mandatory)]
        [string] $DisplayName,

        [Parameter()]
        [string] $Id
    )

    $identifier = $DisplayName.ToLowerInvariant() -replace '[^a-z0-9]+', '-'
    $identifier = $identifier.Trim('-')
    if ([string]::IsNullOrWhiteSpace($identifier)) {
        $identifier = 'unnamed'
    }

    $idSuffix = $null
    if (-not [string]::IsNullOrWhiteSpace($Id)) {
        $idSuffix = ($Id -replace '[^a-zA-Z0-9]', '')
        if ($idSuffix.Length -gt 8) {
            $idSuffix = $idSuffix.Substring(0, 8)
        }
    }
    if (-not [string]::IsNullOrWhiteSpace($idSuffix)) {
        $idSuffix = $idSuffix.ToLowerInvariant()
        $maximumBaseLength = 80 - $idSuffix.Length - 1
    }
    else {
        $maximumBaseLength = 80
    }
    if ($identifier.Length -gt $maximumBaseLength) {
        $identifier = $identifier.Substring(0, $maximumBaseLength).TrimEnd('-')
    }
    if (-not [string]::IsNullOrWhiteSpace($idSuffix)) {
        $identifier = "$identifier-$idSuffix"
    }
    if ([string]::IsNullOrWhiteSpace($identifier)) {
        $identifier = 'unnamed'
    }
    return $identifier
}
