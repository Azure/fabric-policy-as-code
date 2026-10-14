function Write-FpacDeploymentPlan {
    param (
        [Parameter(Mandatory)]
        [System.Collections.IDictionary] $Plan,

        [Parameter(Mandatory)]
        [string] $Path
    )

    if ($Plan.numberOfChanges -eq 0) {
        if (Test-Path -LiteralPath $Path -PathType Leaf) {
            Remove-Item -LiteralPath $Path -Force
        }
        return 'no'
    }

    $parent = Split-Path -Parent $Path
    if (-not (Test-Path -LiteralPath $parent -PathType Container)) {
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
    }
    $Plan | ConvertTo-Json -Depth 100 |
        Set-Content -LiteralPath $Path -Encoding utf8
    return 'yes'
}
