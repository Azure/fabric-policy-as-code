Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$script:FabricApiBaseUri = 'https://api.fabric.microsoft.com/v1'
$script:MaxRetryAttempts = 5

$script:PackageRoot = $PSScriptRoot
if (-not (Test-Path -LiteralPath (Join-Path $script:PackageRoot 'scripts\helpers') -PathType Container)) {
    $script:PackageRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
}

foreach ($file in Get-ChildItem -LiteralPath (Join-Path $script:PackageRoot 'scripts\helpers') -Filter '*.ps1' -File | Sort-Object Name) {
    . $file.FullName
}
foreach ($file in Get-ChildItem -LiteralPath (Join-Path $PSScriptRoot 'Public') -Filter '*.ps1' -File | Sort-Object Name) {
    . $file.FullName
}

Export-ModuleMember -Function Export-FpacPolicy, New-FpacPolicyPlan, Invoke-FpacPolicyDeployment
