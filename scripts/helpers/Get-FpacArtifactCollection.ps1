function Get-FpacArtifactCollection {
    param (
        [Parameter(Mandatory)]
        [string] $Path
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Container)) {
        throw "FPAC artifact folder was not found: $Path"
    }

    $artifacts = [ordered]@{}
    foreach ($file in @(Get-ChildItem -LiteralPath $Path -File | Where-Object { $_.Extension -in @('.json', '.jsonc') } | Sort-Object Name)) {
        $document = $null
        try {
            $options = [System.Text.Json.JsonDocumentOptions]::new()
            $options.CommentHandling = [System.Text.Json.JsonCommentHandling]::Skip
            $options.AllowTrailingCommas = $true
            $document = [System.Text.Json.JsonDocument]::Parse((Get-Content -LiteralPath $file.FullName -Raw), $options)
            $artifact = ConvertFrom-FpacJsonElement -Element $document.RootElement
        }
        catch {
            throw "Unable to parse FPAC artifact '$($file.FullName)': $($_.Exception.Message)"
        }
        finally {
            if ($null -ne $document) {
                $document.Dispose()
            }
        }

        if ([string]::IsNullOrWhiteSpace([string] $artifact.name) -or $null -eq $artifact.properties) {
            throw "FPAC artifact '$($file.FullName)' must contain name and properties."
        }
        if ($artifacts.Contains([string] $artifact.name)) {
            throw "Duplicate FPAC artifact name '$($artifact.name)' in '$Path'."
        }
        $artifacts[[string] $artifact.name] = $artifact
    }
    return $artifacts
}
