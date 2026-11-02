# Packaging, documentation, and releases

## One-time maintainer setup

1. Reserve/verify ownership of the `FabricPolicyAsCode` PowerShell Gallery
   package name. It is the manifest name and public install contract.
2. Create the GitHub environment **powershell-gallery**. Restrict it to
   protected version tags; require maintainer approval and prevent self-review
   where available.
3. Add `PSGALLERY_API_KEY` as an environment secret. Scope the Gallery key to
   this package and the required publish operations, set an expiry, and rotate
   it. Gallery publication does not use Fabric's OIDC identity.
4. In repository **Settings > Pages**, select **GitHub Actions** as the build
   source. Protect the **github-pages** environment and allow the release tags
   used by the workflow.
5. Protect release tags (`v*`) against deletion/movement and restrict who can
   publish releases. Protect workflow/manifest changes through code review.

No Fabric credentials belong in the product release workflow. The deploy
actions authenticate in each consumer repository instead.

## Release

1. Complete relevant live validation; mocked tests do not certify Fabric
   preview permissions or enforcement.
2. Update `ModuleVersion` and manifest `ReleaseNotes` in
   `Module/FabricPolicyAsCode/FabricPolicyAsCode.psd1`. Update version examples
   and consumer workflow pins for the new release.
3. Merge reviewed code and documentation. Run the package and docs checks.
4. Create an immutable tag `vX.Y.Z` on that commit and **publish a GitHub
   release** for it. Creating a tag alone does not publish the package.
5. Approve the `powershell-gallery` environment after the build checks pass.

The release workflow:

1. Rejects a tag that does not exactly match the manifest version.
2. Runs Pester, builds an allowlisted staging package, validates its manifest,
   and imports the staged module.
3. Builds the documentation in strict mode from the same release commit,
   stamping it with the module version and source commit.
4. Publishes the staged package to Gallery. An independent job attaches a
   versioned ZIP to the GitHub release; ZIP upload failure cannot block the
   documentation update after successful Gallery publication.
5. Deploys the already-built documentation artifact to GitHub Pages **only
   after** Gallery publication succeeds.

The public site at
<https://azure.github.io/fabric-policy-as-code/> therefore describes the latest
successfully published package, not arbitrary unreleased changes on `main`.
The site includes a generated **Package version** page. Earlier release
documentation remains available in the corresponding repository tag; this
initial implementation does not host side-by-side versioned websites.

Gallery and Pages are separate systems, not a transactional publish. If Pages
fails after package publication, rerun the failed Pages job; do not republish or
change the package version's contents. If ZIP upload fails, rerun the failed attachment job or attach the already-built
ZIP from the run artifact. Never move a published tag to repair a release.
Gallery versions are immutable. Re-running a successful Gallery publish will
fail rather than silently overwrite the version.

## Local checks

```powershell
$package = .\Module\build.ps1 -OutputPath .\.build\release-check
Test-ModuleManifest (Join-Path $package 'FabricPolicyAsCode.psd1')
Import-Module (Join-Path $package 'FabricPolicyAsCode.psd1') -Force
Invoke-Pester -Path .\tests

python -m pip install -r requirements-docs.txt
.\scripts\Build-Documentation.ps1
python -m mkdocs build --strict
python -m mkdocs serve
```

The documentation builder stages only public docs, schemas, the example
workflow, and selected root documentation. It never copies `Definitions`,
`Definitionsold`, `Output`, or local credentials. Package and docs staging use
`.build`, which is ignored by Git.

PR validation builds the site without publishing it. Documentation changes
become public with the next package release.
