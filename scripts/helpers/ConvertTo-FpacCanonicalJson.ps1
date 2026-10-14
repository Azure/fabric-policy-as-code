function ConvertTo-FpacCanonicalJson {
    param (
        [Parameter()]
        [AllowNull()]
        [object] $InputObject
    )

    return ConvertTo-FpacCanonicalObject -InputObject $InputObject |
        ConvertTo-Json -Depth 100 -Compress
}
