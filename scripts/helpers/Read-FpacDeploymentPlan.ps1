function Read-FpacDeploymentPlan {
    param (
        [Parameter(Mandatory)]
        [string] $Path,

        [Parameter(Mandatory)]
        [string] $SchemaPath
    )

    $resolvedPath = [System.IO.Path]::GetFullPath($Path)
    if (-not (Test-Path -LiteralPath $resolvedPath -PathType Leaf)) {
        throw "FPAC deployment plan was not found: $resolvedPath"
    }
    if (-not (Test-Path -LiteralPath $SchemaPath -PathType Leaf)) {
        throw "FPAC deployment plan schema was not found: $SchemaPath"
    }

    $json = Get-Content -LiteralPath $resolvedPath -Raw
    if (-not (Test-Json -Json $json -SchemaFile $SchemaPath)) {
        throw "FPAC deployment plan failed schema validation: $resolvedPath"
    }

    try {
        return $json | ConvertFrom-Json -Depth 100 -ErrorAction Stop
    }
    catch {
        throw "Unable to parse FPAC deployment plan '$resolvedPath': $($_.Exception.Message)"
    }
}
