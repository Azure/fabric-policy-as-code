[CmdletBinding()]
param (
    [string] $OutputPath = (Join-Path (Split-Path -Parent $PSScriptRoot) '.build\module')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$repositoryRoot = Split-Path -Parent $PSScriptRoot
$source = Join-Path $PSScriptRoot 'FabricPolicyAsCode'
$manifest = Import-PowerShellDataFile -LiteralPath (Join-Path $source 'FabricPolicyAsCode.psd1')
$destination = Join-Path ([System.IO.Path]::GetFullPath($OutputPath)) "FabricPolicyAsCode\$($manifest.ModuleVersion)"
if (Test-Path -LiteralPath $destination) {
    throw "Package destination already exists: $destination. Use a new empty output directory."
}

New-Item -ItemType Directory -Path $destination -Force | Out-Null
Copy-Item -LiteralPath (Join-Path $source 'FabricPolicyAsCode.psd1'), (Join-Path $source 'FabricPolicyAsCode.psm1') -Destination $destination
Copy-Item -LiteralPath (Join-Path $source 'Public') -Destination $destination -Recurse
New-Item -ItemType Directory -Path (Join-Path $destination 'scripts') | Out-Null
Copy-Item -LiteralPath (Join-Path $repositoryRoot 'scripts\helpers') -Destination (Join-Path $destination 'scripts') -Recurse
Copy-Item -LiteralPath (Join-Path $repositoryRoot 'schemas') -Destination $destination -Recurse
Copy-Item -LiteralPath (Join-Path $repositoryRoot 'LICENSE'), (Join-Path $repositoryRoot 'README.md') -Destination $destination
Test-ModuleManifest -Path (Join-Path $destination 'FabricPolicyAsCode.psd1') | Out-Null
Write-Output $destination
