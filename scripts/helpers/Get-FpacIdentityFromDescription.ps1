function Get-FpacIdentityFromDescription {
    param (
        [Parameter()]
        [AllowNull()]
        [string] $Description
    )

    $match = [regex]::Match(
        $Description,
        '\[\[FPAC:v1;(?:owner=[A-Za-z0-9._:-]+;)?id=(?<id>[A-Za-z0-9._:-]+)\]\]'
    )
    if ($match.Success) {
        return $match.Groups['id'].Value
    }
    return ''
}
