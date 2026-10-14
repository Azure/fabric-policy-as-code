function Confirm-FpacOutputReplacement {
    param (
        [Parameter(Mandatory)]
        [string] $DestinationPath,

        [Parameter(Mandatory)]
        [string] $DisplayPath
    )

    $destinationPath = [System.IO.Path]::GetFullPath($DestinationPath)
    if (-not (Test-Path -LiteralPath $destinationPath)) {
        return $true
    }
    if (-not (Test-Path -LiteralPath $destinationPath -PathType Container)) {
        throw "Output scope path '$destinationPath' exists and is not a directory."
    }

    Write-Host "This will delete the existing $DisplayPath folder, continue Y/N?"
    $confirmation = Read-Host 'Y/N'
    if ([string]::Equals($confirmation, 'Y', [System.StringComparison]::OrdinalIgnoreCase)) {
        Remove-Item -LiteralPath $destinationPath -Recurse -Force
        return $true
    }
    if ([string]::Equals($confirmation, 'N', [System.StringComparison]::OrdinalIgnoreCase)) {
        return $false
    }

    throw "Invalid confirmation '$confirmation'. Enter Y to delete the existing output folder or N to cancel."
}
