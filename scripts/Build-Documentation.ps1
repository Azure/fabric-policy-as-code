[CmdletBinding()]
param (
    [string] $ReleaseTag
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$manifest = Import-PowerShellDataFile -LiteralPath (Join-Path $root 'Module\FabricPolicyAsCode\FabricPolicyAsCode.psd1')
$version = [string] $manifest.ModuleVersion
if ($ReleaseTag -and $ReleaseTag -ne "v$version") {
    throw "Release tag '$ReleaseTag' does not match module version '$version'."
}
$destination = Join-Path $root '.build\docs'
if (Test-Path -LiteralPath $destination) {
    Remove-Item -LiteralPath $destination -Recurse -Force
}
New-Item -ItemType Directory -Path $destination -Force | Out-Null
foreach ($name in @('README.md', 'CONTRIBUTING.md', 'SECURITY.md', 'CODE_OF_CONDUCT.md', 'LICENSE')) {
    Copy-Item -LiteralPath (Join-Path $root $name) -Destination $destination
}
Copy-Item -LiteralPath (Join-Path $root 'docs'), (Join-Path $root 'schemas') -Destination $destination -Recurse
New-Item -ItemType Directory -Path (Join-Path $destination 'examples\workflows') -Force | Out-Null
Copy-Item -LiteralPath (Join-Path $root 'examples\workflows\fpac-plan-deploy.yml') -Destination (Join-Path $destination 'examples\workflows')
$commit = git -C $root rev-parse HEAD
if ($LASTEXITCODE -ne 0) { throw 'Unable to identify the documentation source commit.' }
$status = if ($ReleaseTag) { "Published package: **$version** ($ReleaseTag)." } else { "Development documentation for package version **$version**; not evidence of publication." }
@"
# Package version

$status

Source commit: ``$commit``.

The release workflow builds this site from the same commit as the package and
deploys it only after PowerShell Gallery publication succeeds.

Install the matching published package:

``````powershell
Install-Module FabricPolicyAsCode -RequiredVersion $version -Scope CurrentUser
``````
"@ | Set-Content -LiteralPath (Join-Path $destination 'docs\package-version.md') -Encoding utf8
