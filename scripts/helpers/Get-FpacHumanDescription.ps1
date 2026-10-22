function Get-FpacHumanDescription {
    param (
        [Parameter()]
        [AllowNull()]
        [string] $Description
    )

    if ([string]::IsNullOrWhiteSpace($Description)) {
        return ''
    }
    return ([regex]::Replace(
        $Description,
        '\s*\[\[FPAC:v1;(?:owner=[A-Za-z0-9._:-]+;)?id=[A-Za-z0-9._:-]+\]\]\s*$',
        ''
    )).TrimEnd()
}
