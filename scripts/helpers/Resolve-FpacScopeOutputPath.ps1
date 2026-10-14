function Resolve-FpacScopeOutputPath {
    param (
        [Parameter(Mandatory)]
        [string] $OutputRoot,

        [Parameter(Mandatory)]
        [string] $ScopeName
    )

    $outputRootPath = [System.IO.Path]::GetFullPath($OutputRoot)
    $scopeFolderName = ConvertTo-SafePathSegment -Value $ScopeName
    $outputFolderName = [System.IO.Path]::GetFileName($outputRootPath.TrimEnd(
            [System.IO.Path]::DirectorySeparatorChar,
            [System.IO.Path]::AltDirectorySeparatorChar
        ))
    if ([string]::Equals($outputFolderName, $scopeFolderName, [System.StringComparison]::OrdinalIgnoreCase)) {
        return $outputRootPath
    }

    return [System.IO.Path]::GetFullPath((Join-Path $outputRootPath $scopeFolderName))
}
