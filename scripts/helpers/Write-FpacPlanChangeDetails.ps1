function Write-FpacPlanChangeDetails {
    param (
        [Parameter(Mandatory)]
        [string] $ResourceType,

        [Parameter(Mandatory)]
        [System.Collections.IDictionary] $ResourcePlan,

        [Parameter()]
        [switch] $DetailedOutput,

        [Parameter()]
        [System.Collections.IDictionary] $CapacityMap = @{}
    )

    if ($ResourcePlan.numberOfChanges -eq 0) {
        return
    }

    Write-FpacModernSection -Title "$ResourceType Change Details"
    foreach ($action in @('new', 'update', 'replace', 'adopt', 'delete')) {
        foreach ($name in @($ResourcePlan[$action].Keys) | Sort-Object) {
            $status = switch ($action) {
                'new' { 'success' }
                'update' { 'update' }
                'replace' { 'warning' }
                'adopt' { 'warning' }
                'delete' { 'error' }
            }
            $label = $action.Substring(0, 1).ToUpperInvariant() + $action.Substring(1)
            $entry = $ResourcePlan[$action][$name]
            $resource = if ($action -in @('new', 'delete')) { $entry } else { $entry.desired }
            $resourceLabel = "$($resource.properties.workspace)/$($resource.properties.displayName)"
            $differences = if ($action -in @('update', 'replace', 'adopt')) { @($entry.differences) } else { @() }
            $changedPaths = @($differences | ForEach-Object {
                Format-FpacPlanPropertyPath -Path $_.path -Summary
            } | Sort-Object -Unique)
            $suffix = if ($changedPaths.Count -gt 0) { " ($($changedPaths -join ', '))" } else { '' }
            Write-FpacModernStatus -Message "$label$suffix`: $resourceLabel" -Status $status -Indent 2

            if (-not $DetailedOutput -or $action -eq 'delete') {
                continue
            }
            if ($action -eq 'new') {
                Write-FpacDetailedChanges -ResourceType $ResourceType -Action New -Name $resourceLabel -Desired $entry -CapacityMap $CapacityMap
            }
            else {
                Write-FpacDetailedChanges -ResourceType $ResourceType `
                    -Action $label -Name $resourceLabel -Desired $entry.desired -Deployed $entry.deployed `
                    -ChangedFields $entry.changes -Differences $differences -CapacityMap $CapacityMap
            }
        }
    }
}
