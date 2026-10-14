function Get-FpacSchemaReference {
    param (
        [Parameter(Mandatory)]
        [string] $ArtifactDirectory,

        [Parameter(Mandatory)]
        [string] $SchemaPath
    )

    $artifactDirectoryPath = [System.IO.Path]::GetFullPath($ArtifactDirectory)
    $schemaFilePath = [System.IO.Path]::GetFullPath($SchemaPath)
    $reference = [System.IO.Path]::GetRelativePath($artifactDirectoryPath, $schemaFilePath)

    if ([System.IO.Path]::IsPathRooted($reference)) {
        return ([System.Uri] $schemaFilePath).AbsoluteUri
    }

    return $reference.Replace('\', '/')
}
