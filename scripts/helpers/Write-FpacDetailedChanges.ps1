function Write-FpacDetailedChanges {
    param (
        [Parameter(Mandatory)]
        [string] $ResourceType,

        [Parameter(Mandatory)]
        [ValidateSet('New', 'Update', 'Replace', 'Adopt', 'Delete')]
        [string] $Action,

        [Parameter(Mandatory)]
        [string] $Name,

        [Parameter()]
        [AllowNull()]
        [object] $Desired,

        [Parameter()]
        [AllowNull()]
        [object] $Deployed,

        [Parameter()]
        [string[]] $ChangedFields = @(),

        [Parameter()]
        [object[]] $Differences = @()
    )

    Write-FpacModernStatus -Message "[$ResourceType] Detailed Changes for: $Name" -Status info -Indent 6
    if ($Action -eq 'New') {
        foreach ($line in (($Desired.properties | ConvertTo-Json -Depth 100) -split '\r?\n')) {
            Write-FpacColoredOutput -Message "        + $line" -Color Green
        }
        return
    }
    if ($Action -eq 'Delete') {
        foreach ($line in (($Deployed.properties | ConvertTo-Json -Depth 100) -split '\r?\n')) {
            Write-FpacColoredOutput -Message "        - $line" -Color Red
        }
        return
    }

    if ($Differences.Count -eq 0) {
        $Differences = @(Get-FpacObjectDifferences -Desired $Desired.properties -Deployed $Deployed.properties -Path 'properties')
    }
    foreach ($difference in $Differences) {
        Write-FpacModernStatus -Message "Property: $($difference.path)" -Status info -Indent 8
        if ($difference.change -in @('Remove', 'Replace')) {
            $oldValue = if ($difference.oldValue -is [string]) {
                $difference.oldValue
            }
            else {
                $difference.oldValue | ConvertTo-Json -Depth 100 -Compress
            }
            Write-FpacColoredOutput -Message "          - $oldValue" -Color Red
        }
        if ($difference.change -in @('Add', 'Replace')) {
            $newValue = if ($difference.newValue -is [string]) {
                $difference.newValue
            }
            else {
                $difference.newValue | ConvertTo-Json -Depth 100 -Compress
            }
            Write-FpacColoredOutput -Message "          + $newValue" -Color Green
        }
    }
}
