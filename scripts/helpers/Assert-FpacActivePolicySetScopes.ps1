function Assert-FpacActivePolicySetScopes {
    param (
        [Parameter(Mandatory)]
        [System.Collections.IDictionary] $PolicySets
    )

    $activeScopes = [System.Collections.Hashtable]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($policySet in $PolicySets.Values) {
        if ([string] $policySet.properties.status -ne 'Active') {
            continue
        }
        $scopeKey = Get-FpacScopeKey -Scope $policySet.properties.scope
        if ($scopeKey -eq 'Capacity:Unbound') {
            throw "Active Policy Set '$($policySet.name)' must specify a capacity."
        }
        if ($activeScopes.ContainsKey($scopeKey)) {
            throw "Policy Sets '$($activeScopes[$scopeKey])' and '$($policySet.name)' are both Active for scope '$scopeKey'. Only one Policy Set can be active per administrative scope."
        }
        $activeScopes[$scopeKey] = [string] $policySet.name
    }
}
