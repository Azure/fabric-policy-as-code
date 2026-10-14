function Write-FpacPlanChangeDetails {
    param (
        [Parameter(Mandatory)]
        [string] $ResourceType,

        [Parameter(Mandatory)]
        [System.Collections.IDictionary] $ResourcePlan,

        [Parameter()]
        [switch] $DetailedOutput
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
            $differences = if ($action -in @('update', 'replace', 'adopt')) { @($entry.differences) } else { @() }
            $changedPaths = @($differences | ForEach-Object path | Sort-Object -Unique)
            $suffix = if ($changedPaths.Count -gt 0) { " ($($changedPaths -join ', '))" } else { '' }
            Write-FpacModernStatus -Message "$label$suffix`: $name" -Status $status -Indent 2

            if (-not $DetailedOutput) {
                continue
            }
            if ($action -eq 'new') {
                Write-FpacDetailedChanges -ResourceType $ResourceType -Action New -Name $name -Desired $entry
            }
            elseif ($action -eq 'delete') {
                Write-FpacDetailedChanges -ResourceType $ResourceType -Action Delete -Name $name -Deployed $entry
            }
            else {
                Write-FpacDetailedChanges -ResourceType $ResourceType `
                    -Action $label -Name $name -Desired $entry.desired -Deployed $entry.deployed `
                    -ChangedFields $entry.changes -Differences $differences
            }
        }
    }
}
