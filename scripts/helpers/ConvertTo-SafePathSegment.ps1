function ConvertTo-SafePathSegment {
    param (
        [Parameter()]
        [AllowEmptyString()]
        [string] $Value
    )

    if ([string]::IsNullOrWhiteSpace($Value)) {
        return 'unnamed'
    }

    $safeValue = $Value -replace '[<>:"/\\|?*\x00-\x1F]', '_'
    $safeValue = $safeValue.Trim().TrimEnd('.')
    if ([string]::IsNullOrWhiteSpace($safeValue)) {
        return 'unnamed'
    }

    if ($safeValue.Length -gt 80) {
        $safeValue = $safeValue.Substring(0, 80)
    }
    return $safeValue
}
