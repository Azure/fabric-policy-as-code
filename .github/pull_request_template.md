## Summary

Describe the problem and the user-visible or engineering change.

## Related issue

Link the issue this pull request addresses, if applicable.

## Validation

Describe the commands and environments used to validate the change.

- [ ] Relevant Pester tests pass.
- [ ] New or changed behavior has automated coverage.
- [ ] Live Fabric validation is documented when an API contract changed.
- [ ] Documentation is updated when behavior, configuration, or permissions changed.
- [ ] `git diff --check` passes.
- [ ] No credentials, tokens, tenant-specific definitions, customer data, generated plans, or exported live state are included.

## Deployment and safety impact

Describe any effect on:

- Export completeness or generated artifacts.
- Plan classification or detailed differences.
- Ownership and adoption.
- Activation or deactivation.
- Replacement or deletion.
- Stale-plan validation.
- Tenant or capacity boundaries.

Write `None` when the change has no deployment or safety impact.

## Checklist

- [ ] The change is focused and excludes unrelated refactoring.
- [ ] Error conditions remain explicit and actionable.
- [ ] Existing behavior is preserved unless the change is intentional and documented.
- [ ] I have reviewed and take responsibility for all submitted content, including any AI-assisted content.
