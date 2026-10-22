function Get-FpacGlobalSettings {
    param (
        [Parameter(Mandatory)]
        [string] $Path
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "FPAC global settings file was not found: $Path"
    }

    $document = $null
    try {
        $jsonOptions = [System.Text.Json.JsonDocumentOptions]::new()
        $jsonOptions.CommentHandling = [System.Text.Json.JsonCommentHandling]::Skip
        $jsonOptions.AllowTrailingCommas = $true
        $document = [System.Text.Json.JsonDocument]::Parse((Get-Content -LiteralPath $Path -Raw), $jsonOptions)
        $settings = ConvertFrom-FpacJsonElement -Element $document.RootElement
    }
    catch {
        throw "Unable to parse FPAC global settings '$Path': $($_.Exception.Message)"
    }
    finally {
        if ($null -ne $document) {
            $document.Dispose()
        }
    }

    $configuredEnvironments = @(Get-FabricPropertyValue -InputObject $settings -Name 'environments')
    if ($configuredEnvironments.Count -eq 0) {
        throw "Add at least one environment to 'environments' in '$Path'."
    }
    $pacOwnerId = [string] (Get-FabricPropertyValue -InputObject $settings -Name 'pacOwnerId')
    if ([string]::IsNullOrWhiteSpace($pacOwnerId)) {
        $pacOwnerId = 'fpac'
    }
    elseif ($pacOwnerId -notmatch '^[A-Za-z0-9._:-]+$') {
        throw "Set pacOwnerId in '$Path' to a non-empty value containing only letters, numbers, period, underscore, colon, or hyphen."
    }
    $desiredStateStrategy = [string] (Get-FabricPropertyValue -InputObject $settings -Name 'desiredStateStrategy')
    if ([string]::IsNullOrWhiteSpace($desiredStateStrategy)) {
        $desiredStateStrategy = 'OwnedOnly'
    }
    elseif ($desiredStateStrategy -notin @('OwnedOnly', 'Full')) {
        throw "Set desiredStateStrategy in '$Path' to OwnedOnly or Full."
    }

    $environments = [System.Collections.Generic.List[object]]::new()
    $environmentNames = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($environment in $configuredEnvironments) {
        $name = [string] (Get-FabricPropertyValue -InputObject $environment -Name 'name')
        if ([string]::IsNullOrWhiteSpace($name)) {
            throw "Every environment in '$Path' must have a non-empty name."
        }
        if (-not $environmentNames.Add($name)) {
            throw "Environment name '$name' occurs more than once in '$Path'."
        }

        $tenantId = [string] (Get-FabricPropertyValue -InputObject $environment -Name 'tenantId')
        $parsedTenantId = [guid]::Empty
        if (-not [guid]::TryParse($tenantId, [ref] $parsedTenantId)) {
            throw "Set environments[].tenantId for environment '$name' in '$Path' to a tenant GUID."
        }

        $configuredScopes = @(Get-FabricPropertyValue -InputObject $environment -Name 'scope')
        if ($configuredScopes.Count -eq 0) {
            throw "Add at least one entry to environments[].scope for environment '$name'."
        }

        $scopes = [System.Collections.Generic.List[object]]::new()
        $scopeTypes = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
        $capacityNames = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
        foreach ($scope in $configuredScopes) {
            $scopeType = [string] (Get-FabricPropertyValue -InputObject $scope -Name 'type')
            if ([string]::IsNullOrWhiteSpace($scopeType)) {
                $scopeType = 'Capacity'
            }
            elseif ($scopeType -ne 'Tenant') {
                throw "Only tenant scope entries may specify environments[].scope[].type in environment '$name'."
            }
            $null = $scopeTypes.Add($scopeType)

            if ($scopeType -eq 'Capacity') {
                if ($null -ne $scope.PSObject.Properties['includeCapacities']) {
                    throw "includeCapacities is only valid on tenant scope entries in environment '$name'."
                }
                $capacityName = [string] (Get-FabricPropertyValue -InputObject $scope -Name 'name')
                if ([string]::IsNullOrWhiteSpace($capacityName)) {
                    throw "A non-empty environments[].scope[].name is required for capacity environment '$name'."
                }
                if (-not $capacityNames.Add($capacityName)) {
                    throw "Capacity name '$capacityName' occurs more than once in environment '$name'."
                }
                $scopes.Add([pscustomobject]@{
                    Type = 'Capacity'
                    Name = $capacityName
                    CapacityId = $null
                })
            }
            else {
                $includeCapacities = Get-FabricPropertyValue -InputObject $scope -Name 'includeCapacities'
                if ($includeCapacities -isnot [bool]) {
                    throw "Tenant environment '$name' must explicitly set environments[].scope[].includeCapacities to true or false."
                }
                $scopes.Add([pscustomobject]@{
                    Type = 'Tenant'
                    CapacityId = $null
                    IncludeCapacities = $includeCapacities
                })
            }
        }
        if ($scopeTypes.Count -ne 1) {
            throw "Environment '$name' cannot mix tenant and capacity entries in environments[].scope."
        }
        $scopeType = @($scopeTypes)[0]
        if ($scopeType -eq 'Tenant' -and $scopes.Count -ne 1) {
            throw "Tenant environment '$name' must contain exactly one tenant scope entry."
        }

        $environments.Add([pscustomobject]@{
            Name       = $name
            TenantId   = $parsedTenantId.ToString()
            ScopeType  = $scopeType
            Scopes     = $scopes.ToArray()
            CapacityIds = @()
        })
    }

    return [pscustomobject]@{
        PacOwnerId           = $pacOwnerId
        DesiredStateStrategy = $desiredStateStrategy
        Environments         = $environments.ToArray()
    }
}
