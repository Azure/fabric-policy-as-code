BeforeAll {
    . (Join-Path $PSScriptRoot '..\scripts\Deploy\Build-DeploymentPlans.ps1')
}

Describe 'JSONC definition discovery and parsing' {
    It 'reads JSONC and legacy JSON together in <Folder>' -ForEach @(
        @{ Folder = 'policyDefinitions' }
        @{ Folder = 'policySetDefinitions' }
        @{ Folder = 'policyAssignments' }
    ) {
        $root = Join-Path $TestDrive $Folder
        New-Item -ItemType Directory -Path $root -Force | Out-Null
        @'
// Line comment
{
  "name": "commented",
  /* Block comment */
  "properties": {
    "description": "https://example.test/path//text",
    "values": ["one",],
  },
}
'@ | Set-Content -LiteralPath (Join-Path $root 'commented.jsonc')
        '{"name":"legacy","properties":{}}' | Set-Content -LiteralPath (Join-Path $root 'legacy.json')

        $artifacts = Get-FpacArtifactCollection -Path $root

        $artifacts.Count | Should -Be 2
        $artifacts.commented.properties.description | Should -Be 'https://example.test/path//text'
        $artifacts.commented.properties.values.Count | Should -Be 1
        $artifacts.commented.properties.values[0] | Should -Be 'one'
        $artifacts.Contains('legacy') | Should -BeTrue
    }

    It 'rejects duplicate identities across JSON and JSONC instead of silently preferring one' {
        $root = Join-Path $TestDrive 'duplicates'
        New-Item -ItemType Directory -Path $root -Force | Out-Null
        foreach ($extension in @('json', 'jsonc')) {
            '{"name":"duplicate","properties":{}}' | Set-Content -LiteralPath (Join-Path $root "definition.$extension")
        }
        { Get-FpacArtifactCollection -Path $root } | Should -Throw '*Duplicate FPAC artifact name*'
    }

    It 'reports invalid JSONC with the source filename' {
        $root = Join-Path $TestDrive 'invalid'
        New-Item -ItemType Directory -Path $root -Force | Out-Null
        '// Comment' + "`n" + '{"name":"invalid","properties":' |
            Set-Content -LiteralPath (Join-Path $root 'invalid.jsonc')
        { Get-FpacArtifactCollection -Path $root } | Should -Throw '*Unable to parse FPAC artifact*invalid.jsonc*'
    }
}
