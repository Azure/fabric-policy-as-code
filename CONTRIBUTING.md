# Contributing to FPAC

FPAC welcomes bug reports, documentation improvements, tests, and code
contributions. FPAC manages governance resources and can activate or remove
Microsoft Fabric Policy Sets, so correctness, safety, and reviewability take
priority over minimizing implementation effort.

## Contributor License Agreement

Most contributions require agreement to a Contributor License Agreement (CLA)
declaring that you have the right to, and do, grant Microsoft the rights to use
your contribution. For details, visit
<https://cla.opensource.microsoft.com/>.

When you submit a pull request, the CLA bot determines whether a CLA is required
and adds an appropriate status check or comment. Follow the instructions from
the bot. You normally need to complete this only once across repositories that
use the Microsoft CLA.

## Code of Conduct

This project has adopted the
[Microsoft Open Source Code of Conduct](https://opensource.microsoft.com/codeofconduct/).
See the [Code of Conduct FAQ](https://opensource.microsoft.com/codeofconduct/faq/)
or contact [opencode@microsoft.com](mailto:opencode@microsoft.com) with questions
or concerns.

## Before opening an issue

Search existing issues and pull requests before creating a new issue.

For a product bug, include:

- The FPAC commit or release version.
- PowerShell version.
- Operating system.
- Whether the operation was export, planning, or deployment.
- The FPAC environment scope type: tenant or capacity.
- Expected and actual behavior.
- Minimal reproduction steps.
- Sanitized error output.

Do not include:

- Access tokens or authorization headers.
- Client secrets, certificates, or PowerShell Gallery keys.
- Customer data.
- Internal tenant or subscription information that is not necessary to reproduce
  the issue.
- Complete exports from a production tenant.

Report suspected security vulnerabilities privately according to
[SECURITY.md](SECURITY.md), not through a public issue.

## Development prerequisites

Install:

- [Git](https://git-scm.com/).
- [PowerShell 7.4 or later](https://learn.microsoft.com/powershell/scripting/install/installing-powershell).
- [Pester 5.7.1](https://pester.dev/) for the current CI test suite.
- `Az.Accounts` only when performing authorized live Fabric integration testing.

Install the test dependency:

```powershell
Install-Module Pester `
  -RequiredVersion 5.7.1 `
  -Scope CurrentUser `
  -Force `
  -SkipPublisherCheck
```

Install the optional live-authentication dependency:

```powershell
Install-Module Az.Accounts -Scope CurrentUser
```

## Fork and clone

External contributors should fork the repository and clone their fork:

```powershell
gh repo fork Azure/fabric-policy-as-code --clone
Set-Location .\fabric-policy-as-code
git remote add upstream https://github.com/Azure/fabric-policy-as-code.git
```

Before beginning work:

```powershell
git fetch upstream
git switch main
git pull --ff-only upstream main
git switch -c <short-purposeful-branch-name>
```

Use a focused branch for one logical change. Do not reuse a branch after its pull
request has been merged.

## Repository layout

| Path | Purpose |
| --- | --- |
| `scripts/operations/` | Operator-facing export operations |
| `scripts/Deploy/` | Operator-facing plan and deployment operations |
| `scripts/helpers/` | Shared implementation functions |
| `schemas/` | Canonical FPAC JSON schemas |
| `tests/` | Pester tests |
| `docs/` | Project and operator documentation |

The following local directories are intentionally ignored:

- `Definitions/`
- `Definitionsold/`
- `Output/`

Do not force-add those directories. They may contain tenant-specific desired
state, legacy local data, generated deployment plans, or exported live state.
Public examples belong in a sanitized `examples/` directory.

## Coding guidelines

- Make focused changes that address one problem completely.
- Preserve existing behavior unless the pull request intentionally changes and
  documents it.
- Use PowerShell strict mode and terminating error behavior in operator-facing
  entry points.
- Surface errors explicitly. Do not silently convert failures into successful
  results.
- Reuse existing helpers and naming patterns instead of duplicating behavior.
- Preserve type safety and validate external input.
- Keep ownership, adoption, stale-plan, and environment-boundary protections
  intact.
- Treat adoption, activation replacement, and deletion as high-impact
  operations.
- Use portable workspace and capacity names in desired state where FPAC supports
  them.
- Keep comments concise and limited to non-obvious behavior.
- Use ASCII unless an existing file or user-facing requirement needs Unicode.
- Do not include unrelated formatting or refactoring in a functional change.

## Running tests

From the repository root:

```powershell
$configuration = New-PesterConfiguration
$configuration.Run.Path = './tests'
$configuration.Run.PassThru = $true
$configuration.Output.Verbosity = 'Detailed'
$configuration.TestResult.Enabled = $true
$configuration.TestResult.OutputFormat = 'NUnitXml'
$configuration.TestResult.OutputPath = 'TestResults.xml'

$result = Invoke-Pester -Configuration $configuration
if ($result.FailedCount -gt 0) {
    throw "$($result.FailedCount) Pester test(s) failed."
}
```

Do not commit `TestResults.xml`.

Add or update tests when changing:

- Artifact parsing or materialization.
- Environment or scope validation.
- Plan classification.
- Ownership and adoption behavior.
- Activation or replacement behavior.
- API request, retry, or long-running-operation behavior.
- Export completeness and manifest behavior.
- Error messages relied upon by operators or automation.

Mocked tests do not replace authorized live validation for changes to Fabric API
contracts. Describe any live validation in the pull request without attaching
sensitive output.

## Documentation

Update documentation when changing:

- Command parameters or defaults.
- Settings or schema fields.
- File formats.
- Ownership or desired-state behavior.
- Authentication or permissions.
- Plan actions.
- Deployment safeguards.
- Supported Fabric API behavior.

Run any documentation validation workflow included by the repository before
requesting review.

## Commit and pull-request guidance

Before committing:

```powershell
git status --short
git diff --check
```

Keep commit messages concise and action-oriented. A pull request should:

- Explain the problem and solution.
- Remain limited to one logical change.
- Link related issues.
- Include tests for changed behavior.
- Report the exact validation performed.
- Describe effects on export, planning, deployment, ownership, adoption,
  activation, replacement, or deletion.
- Contain no secrets, tenant-specific definitions, generated plans, or customer
  data.
- Pass the Pester and CLA checks.

Maintainers may request changes when behavior is not adequately tested, safety
properties are weakened, documentation is incomplete, or the contribution
includes unrelated changes.

## Generative AI

Contributors are responsible for all submitted content, including content
created with generative AI tools. Review, understand, test, and revise generated
code and documentation before submitting it. Do not send repository secrets,
customer data, or nonpublic Microsoft information to unapproved systems.

## License

By contributing to FPAC, you agree that your contribution will be licensed under
the repository's license.
