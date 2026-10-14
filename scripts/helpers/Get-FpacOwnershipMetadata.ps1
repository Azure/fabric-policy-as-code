function Get-FpacOwnershipMetadata {
    param (
        [Parameter()]
        [AllowNull()]
        [string] $Description
    )

    if ([string]::IsNullOrWhiteSpace($Description)) {
        return $null
    }
    $match = [regex]::Match(
        $Description,
        '\[\[FPAC:v1;owner=(?<owner>[A-Za-z0-9._:-]+);id=(?<id>[A-Za-z0-9._:-]+)\]\]'
    )
    if (-not $match.Success) {
        return $null
    }
    return [pscustomobject]@{
        PacOwnerId = $match.Groups['owner'].Value
        FpacId     = $match.Groups['id'].Value
    }
}
