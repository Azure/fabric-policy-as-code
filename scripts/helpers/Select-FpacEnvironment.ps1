function Select-FpacEnvironment {
    param (
        [Parameter(Mandatory)]
        [object[]] $Environments,

        [Parameter()]
        [string] $EnvironmentName
    )

    if (-not [string]::IsNullOrWhiteSpace($EnvironmentName)) {
        $selected = @($Environments | Where-Object {
            [string]::Equals([string] $_.Name, $EnvironmentName, [System.StringComparison]::OrdinalIgnoreCase)
        })
        if ($selected.Count -ne 1) {
            throw "Environment '$EnvironmentName' is not configured. Choose one of: $(@($Environments.Name) -join ', ')."
        }
        return $selected[0]
    }

    Write-Host 'Select an FPAC environment:'
    for ($index = 0; $index -lt $Environments.Count; $index++) {
        $environment = $Environments[$index]
        $scope = if ($environment.ScopeType -eq 'Capacity') {
            "$(@($environment.Scopes).Count) capacity scope(s)"
        }
        else {
            'Tenant scope'
        }
        Write-Host "  [$($index + 1)] $($environment.Name) - $scope"
    }

    $selection = Read-Host 'Environment number'
    $selectionNumber = 0
    if (-not [int]::TryParse($selection, [ref] $selectionNumber) -or
        $selectionNumber -lt 1 -or $selectionNumber -gt $Environments.Count) {
        throw "Invalid environment selection '$selection'. Enter a number from 1 to $($Environments.Count)."
    }

    return $Environments[$selectionNumber - 1]
}
