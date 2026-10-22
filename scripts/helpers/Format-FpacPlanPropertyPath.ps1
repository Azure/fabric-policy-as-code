function Format-FpacPlanPropertyPath {
    param (
        [Parameter(Mandatory)]
        [string] $Path,

        [Parameter()]
        [switch] $Summary
    )

    switch -Regex ($Path) {
        '^metadata\.pacOwnerId$' { return 'Ownership' }
        '^properties\.policies\[(.+)\]\.metadata\.pacOwnerId$' {
            if ($Summary) { return 'Policy ownership' }
            return "Policy '$($Matches[1])' ownership"
        }
        '^properties\.policies\[(.+)\]\.(.+)$' {
            if ($Summary) { return 'Policies' }
            $policyName = $Matches[1]
            $propertyPath = $Matches[2] -replace '^definition\.', ''
            return "Policy '$policyName': $propertyPath"
        }
        '^properties\.policies' { return 'Policies' }
        '^properties\.scope\.id$' {
            if ($Summary) { return 'Scope' }
            return 'Scope capacity'
        }
        '^properties\.scope\.type$' {
            if ($Summary) { return 'Scope' }
            return 'Scope type'
        }
        '^properties\.scope$' { return 'Scope' }
        '^properties\.status$' { return 'Status' }
        '^properties\.displayName$' { return 'Display name' }
        '^properties\.description$' { return 'Description' }
        '^properties\.workspace$' { return 'Workspace' }
        default { return ($Path -replace '^properties\.', '') }
    }
}
