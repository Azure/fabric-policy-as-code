function Invoke-FabricPolicyExport {
    param (
        [Parameter(Mandatory)]
        [hashtable] $Headers,

        [Parameter(Mandatory)]
        [string] $Destination,

        [Parameter(Mandatory)]
        [pscustomobject] $Target,

        [Parameter()]
        [System.Collections.IDictionary] $CapacityMap = @{},

        [Parameter()]
        [ValidateSet('Exporting', 'Retrieving')]
        [string] $ActivityVerb = 'Exporting'
    )

    $destinationPath = [System.IO.Path]::GetFullPath($Destination)
    if (Test-Path -LiteralPath $destinationPath) {
        if (-not (Test-Path -LiteralPath $destinationPath -PathType Container)) {
            throw "Output path '$destinationPath' exists and is not a directory."
        }

        if (@(Get-ChildItem -LiteralPath $destinationPath -Force).Count -gt 0) {
            throw "Output directory '$destinationPath' is not empty. Choose a new path to avoid overwriting or mixing exports."
        }
    }
    else {
        New-Item -ItemType Directory -Path $destinationPath -Force | Out-Null
    }

    $definitionRoot = Join-Path $destinationPath 'policyDefinitions'
    $policySetRoot = Join-Path $destinationPath 'policySets'
    $assignmentRoot = Join-Path $destinationPath 'assignments'
    foreach ($path in @($definitionRoot, $policySetRoot, $assignmentRoot)) {
        New-Item -ItemType Directory -Path $path -Force | Out-Null
    }
    $schemaRoot = Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) 'schemas'
    foreach ($schemaFile in @('policy-definition.schema.json', 'policy-set.schema.json', 'assignment.schema.json')) {
        $schemaPath = Join-Path $schemaRoot $schemaFile
        if (-not (Test-Path -LiteralPath $schemaPath -PathType Leaf)) {
            throw "FPAC schema file was not found: $schemaPath"
        }
    }
    $policyDefinitionSchemaReference = [System.IO.Path]::GetRelativePath(
        $definitionRoot,
        (Join-Path $schemaRoot 'policy-definition.schema.json')
    ).Replace('\', '/')
    $policySetSchemaReference = [System.IO.Path]::GetRelativePath(
        $policySetRoot,
        (Join-Path $schemaRoot 'policy-set.schema.json')
    ).Replace('\', '/')
    $assignmentSchemaReference = [System.IO.Path]::GetRelativePath(
        $assignmentRoot,
        (Join-Path $schemaRoot 'assignment.schema.json')
    ).Replace('\', '/')

    $exported = [System.Collections.Generic.List[object]]::new()
    $failures = [System.Collections.Generic.List[object]]::new()
    $exportedRuleCount = 0
    $skippedCount = 0
    Write-Host 'Discovering accessible Fabric workspaces...'
    $workspaces = @(Get-FabricPagedCollection -Uri "$script:FabricApiBaseUri/workspaces" -Headers $Headers)
    $workspaceMap = [System.Collections.Hashtable]::new([System.StringComparer]::OrdinalIgnoreCase)
    $workspaceDetails = [System.Collections.Hashtable]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($workspace in $workspaces) {
        $workspaceName = [string] $workspace.displayName
        $workspaceId = [string] $workspace.id
        if ([string]::IsNullOrWhiteSpace($workspaceName) -or [string]::IsNullOrWhiteSpace($workspaceId)) {
            throw 'Fabric returned a workspace without both displayName and id.'
        }
        if ($workspaceMap.ContainsKey($workspaceName)) {
            throw "Fabric returned more than one accessible workspace named '$workspaceName'. FPAC deployment target workspace names must be unique."
        }
        $workspaceMap[$workspaceName] = $workspaceId
        $workspaceDetails[$workspaceName] = [pscustomobject]@{
            Id         = $workspaceId
            CapacityId = [string] (Get-FabricPropertyValue -InputObject $workspace -Name 'capacityId')
        }
    }
    Write-Host "Found $($workspaces.Count) accessible workspace(s). Scanning for Policy Sets..."

    for ($workspaceIndex = 0; $workspaceIndex -lt $workspaces.Count; $workspaceIndex++) {
        $workspace = $workspaces[$workspaceIndex]
        Write-Host "Scanning workspace $($workspaceIndex + 1) of $($workspaces.Count): $($workspace.displayName)"
        try {
            $itemsUri = "$script:FabricApiBaseUri/workspaces/$($workspace.id)/items"
            $items = @(Get-FabricPagedCollection -Uri $itemsUri -Headers $Headers)
        }
        catch {
            $failures.Add([pscustomobject]@{
                workspaceId   = [string] $workspace.id
                workspaceName = [string] $workspace.displayName
                itemId        = $null
                itemName      = $null
                error         = $_.Exception.Message
            })
            continue
        }

        foreach ($item in $items | Where-Object { $_.type -eq 'PolicySet' }) {
            try {
                $policySet = Get-FabricPolicySet -WorkspaceId ([string] $workspace.id) `
                    -PolicySetId ([string] $item.id) -Headers $Headers
                $itemDescription = [string] (Get-FabricPropertyValue -InputObject $item -Name 'description')
                $scope = Get-FabricPropertyValue -InputObject $policySet.properties -Name 'scope'
                $policyScopeType = [string] (Get-FabricPropertyValue -InputObject $scope -Name 'type')
                $policyScopeId = [string] (Get-FabricPropertyValue -InputObject $scope -Name 'id')
                $policyStatus = [string] (Get-FabricPropertyValue -InputObject $policySet.properties -Name 'status')
                if ($policyScopeType -notin @('Tenant', 'Capacity')) {
                    throw "Policy Set '$($item.displayName)' returned unsupported scope type '$policyScopeType'."
                }
                if ($Target.ScopeType -eq 'Capacity' -and
                    ($policyScopeType -ne 'Capacity' -or $policyScopeId -notin @($Target.CapacityIds))) {
                    $skippedCount++
                    continue
                }

                Write-Host "$ActivityVerb Policy Set '$($item.displayName)' from workspace '$($workspace.displayName)'..."
                $policySetName = ConvertTo-FpacIdentifier -DisplayName ([string] $item.displayName) -Id ([string] $item.id)
                $policySetPath = Join-Path $policySetRoot "$policySetName.json"
                $assignmentName = ConvertTo-FpacIdentifier -DisplayName "$($Target.Name)-$($item.displayName)" -Id ([string] $item.id)
                $assignmentPath = Join-Path $assignmentRoot "$assignmentName.json"
                if ((Test-Path -LiteralPath $policySetPath) -or (Test-Path -LiteralPath $assignmentPath)) {
                    throw "An exported Policy Set or assignment already exists for item $($item.id)."
                }

                $rules = @(Get-FabricPolicyRules -WorkspaceId ([string] $workspace.id) `
                    -PolicySetId ([string] $item.id) -Headers $Headers)
                $policyReferences = [System.Collections.Generic.List[object]]::new()
                $assignmentParameters = [ordered]@{}
                foreach ($rule in $rules) {
                    $policyDefinition = ConvertTo-FpacPolicyDefinition -Rule $rule `
                        -SchemaReference $policyDefinitionSchemaReference
                    $definitionPath = Join-Path $definitionRoot "$($policyDefinition.name).json"
                    if (Test-Path -LiteralPath $definitionPath) {
                        throw "An exported policy definition already exists: $($policyDefinition.name)."
                    }
                    $policyReferences.Add([ordered]@{
                        name       = $policyDefinition.name
                        parameters = [ordered]@{}
                    })
                    $policyParameters = [ordered]@{}
                    foreach ($parameter in @($policyDefinition.properties.parameters.GetEnumerator())) {
                        $targetProperty = [string] $parameter.Value.metadata.targetProperty
                        $portableValues = foreach ($value in @($parameter.Value.defaultValue)) {
                            ConvertTo-FpacPortableParameterValue -Value $value `
                                -TargetProperty $targetProperty `
                                -WorkspaceMap $workspaceMap `
                                -CapacityMap $CapacityMap
                        }
                        $portableValue = if ([string] $parameter.Value.type -eq 'Array') {
                            @($portableValues)
                        }
                        else {
                            @($portableValues)[0]
                        }
                        $policyParameters[$parameter.Key] = [ordered]@{
                            value = $portableValue
                        }
                        $parameter.Value.Remove('defaultValue')
                    }
                    if ($policyParameters.Count -gt 0) {
                        $assignmentParameters[$policyDefinition.name] = $policyParameters
                    }
                    Write-FpacJsonFile -Path $definitionPath -Value $policyDefinition
                    $exportedRuleCount++
                }

                $policySetArtifact = [ordered]@{
                    '$schema' = $policySetSchemaReference
                    name      = $policySetName
                    properties = [ordered]@{
                        displayName = [string] $item.displayName
                        description = Get-FpacHumanDescription -Description $itemDescription
                        policies    = @($policyReferences.ToArray())
                    }
                }
                $policySetOwnership = Get-FpacOwnershipMetadata -Description $itemDescription
                if ($null -ne $policySetOwnership) {
                    $policySetArtifact['metadata'] = [ordered]@{
                        pacOwnerId = $policySetOwnership.PacOwnerId
                        fpacId     = $policySetOwnership.FpacId
                    }
                }
                Write-FpacJsonFile -Path $policySetPath -Value $policySetArtifact

                if ($policyScopeType -eq 'Capacity') {
                    if ([string]::IsNullOrWhiteSpace($policyScopeId)) {
                        if ($policyStatus -eq 'Active') {
                            throw "Active capacity Policy Set '$($item.displayName)' did not return a capacity id."
                        }
                        $assignmentScope = [ordered]@{
                            type = 'Capacity'
                        }
                    }
                    else {
                        $capacityNames = @($CapacityMap.Keys | Where-Object {
                            [string]::Equals(
                                [string] $CapacityMap[$_],
                                $policyScopeId,
                                [System.StringComparison]::OrdinalIgnoreCase
                            )
                        })
                        if ($capacityNames.Count -ne 1) {
                            throw "Unable to resolve capacity id '$policyScopeId' to one unique capacity name for assignment export."
                        }
                        $assignmentScope = [ordered]@{
                            name = [string] $capacityNames[0]
                        }
                    }
                }
                else {
                    $assignmentScope = [ordered]@{
                        type = 'Tenant'
                    }
                }
                $assignmentTargets = [ordered]@{}
                $assignmentTargets[[string] $Target.Name] = @(
                    [ordered]@{
                        workspace = [string] $workspace.displayName
                        scope = $assignmentScope
                    }
                )
                $assignment = [ordered]@{
                    '$schema' = $assignmentSchemaReference
                    name      = $assignmentName
                    properties = [ordered]@{
                        policySetName = $policySetName
                        displayName   = [string] $item.displayName
                        status        = $policyStatus
                        parameters    = $assignmentParameters
                        targets       = $assignmentTargets
                    }
                }
                Write-FpacJsonFile -Path $assignmentPath -Value $assignment

                $exported.Add([pscustomobject]@{
                    workspaceId  = [string] $workspace.id
                    workspaceName = [string] $workspace.displayName
                    itemId        = [string] $item.id
                    itemName      = [string] $item.displayName
                    scopeType     = $policyScopeType
                    scopeId       = $policyScopeId
                    status        = [string] (Get-FabricPropertyValue -InputObject $policySet.properties -Name 'status')
                    policyCount   = $rules.Count
                    policySetPath = [System.IO.Path]::GetRelativePath($destinationPath, $policySetPath)
                    assignmentPath = [System.IO.Path]::GetRelativePath($destinationPath, $assignmentPath)
                })
            }
            catch {
                $failures.Add([pscustomobject]@{
                    workspaceId   = [string] $workspace.id
                    workspaceName = [string] $workspace.displayName
                    itemId        = [string] $item.id
                    itemName      = [string] $item.displayName
                    error         = $_.Exception.Message
                })
            }
        }
    }

    $manifest = [ordered]@{
        schemaVersion    = '1.0'
        exportedAtUtc    = [DateTime]::UtcNow.ToString('o')
        environment      = [ordered]@{
            name       = $Target.Name
            tenantId   = $Target.TenantId
            scopes     = @($Target.Scopes | ForEach-Object {
                [ordered]@{
                    type = $_.Type
                    capacityId = $_.CapacityId
                }
            })
        }
        workspaceCount   = $workspaces.Count
        policySetCount   = $exported.Count
        policyCount      = $exportedRuleCount
        skippedScopeCount = $skippedCount
        failureCount     = $failures.Count
        isComplete       = ($failures.Count -eq 0)
        policySets       = @($exported.ToArray())
        failures         = @($failures.ToArray())
    }
    $manifest | ConvertTo-Json -Depth 20 |
        Set-Content -LiteralPath (Join-Path $destinationPath 'manifest.json') -Encoding utf8

    return [pscustomobject]@{
        Destination = $destinationPath
        WorkspaceCount = $workspaces.Count
        ExportedCount = $exported.Count
        PolicyCount = $exportedRuleCount
        SkippedScopeCount = $skippedCount
        FailureCount = $failures.Count
        IsComplete = ($failures.Count -eq 0)
        Failures = $failures.ToArray()
        WorkspaceMap = $workspaceMap
        WorkspaceDetails = $workspaceDetails
    }
}
