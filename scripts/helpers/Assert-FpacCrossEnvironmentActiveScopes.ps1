function Assert-FpacCrossEnvironmentActiveScopes {
    param (
        [Parameter(Mandatory)]
        [System.Collections.IDictionary] $AssignmentDefinitions,

        [Parameter(Mandatory)]
        [object[]] $Environments
    )

    $tenantByEnvironment = [System.Collections.Hashtable]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($environment in $Environments) {
        $tenantByEnvironment[[string] $environment.Name] = [string] $environment.TenantId
    }
    $activeScopes = [System.Collections.Hashtable]::new([System.StringComparer]::OrdinalIgnoreCase)

    foreach ($definition in $AssignmentDefinitions.Values) {
        $childrenProperty = $definition.properties.PSObject.Properties['children']
        $children = if ($null -ne $childrenProperty) {
            @($childrenProperty.Value)
        }
        else {
            @([pscustomobject]@{
                name    = [string] $definition.name
                status  = Get-FabricPropertyValue -InputObject $definition.properties -Name 'status'
                targets = Get-FabricPropertyValue -InputObject $definition.properties -Name 'targets'
            })
        }
        foreach ($child in $children) {
            $status = [string] (Get-FabricPropertyValue -InputObject $child -Name 'status')
            if ([string]::IsNullOrWhiteSpace($status)) {
                $status = 'Active'
            }
            if ($status -ne 'Active' -or $null -eq $child.targets) {
                continue
            }
            foreach ($environmentProperty in @($child.targets.PSObject.Properties)) {
                if (-not $tenantByEnvironment.ContainsKey($environmentProperty.Name)) {
                    continue
                }
                $tenantId = [string] $tenantByEnvironment[$environmentProperty.Name]
                foreach ($target in @($environmentProperty.Value)) {
                    $scope = Get-FabricPropertyValue -InputObject $target -Name 'scope'
                    $scopeType = [string] (Get-FabricPropertyValue -InputObject $scope -Name 'type')
                    if ($scopeType -eq 'Tenant') {
                        $scopeKey = "$tenantId/Tenant"
                    }
                    else {
                        $scopeName = [string] (Get-FabricPropertyValue -InputObject $scope -Name 'name')
                        $scopeId = [string] (Get-FabricPropertyValue -InputObject $scope -Name 'id')
                        $scopeIdentity = if (-not [string]::IsNullOrWhiteSpace($scopeId)) {
                            $scopeId
                        }
                        else {
                            $scopeName
                        }
                        if ([string]::IsNullOrWhiteSpace($scopeIdentity)) {
                            continue
                        }
                        $scopeKey = "$tenantId/Capacity:$($scopeIdentity.ToLowerInvariant())"
                    }
                    $identity = "$($environmentProperty.Name)/$($child.name)"
                    if ($activeScopes.ContainsKey($scopeKey)) {
                        throw "Active Policy Set deployments '$($activeScopes[$scopeKey])' and '$identity' both target '$scopeKey' across FPAC environments."
                    }
                    $activeScopes[$scopeKey] = $identity
                }
            }
        }
    }
}
