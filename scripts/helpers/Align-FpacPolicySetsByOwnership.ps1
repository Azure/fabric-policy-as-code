function Align-FpacPolicySetsByOwnership {
    param (
        [Parameter(Mandatory)]
        [System.Collections.IDictionary] $Desired,

        [Parameter(Mandatory)]
        [System.Collections.IDictionary] $Deployed
    )

    $aligned = [ordered]@{}
    foreach ($key in $Deployed.Keys) {
        $aligned[$key] = $Deployed[$key]
    }
    foreach ($desiredKey in $Desired.Keys) {
        if ($aligned.Contains($desiredKey)) {
            continue
        }
        $desiredMetadata = Get-FabricPropertyValue -InputObject $Desired[$desiredKey] -Name 'metadata'
        $desiredOwner = [string] (Get-FabricPropertyValue -InputObject $desiredMetadata -Name 'pacOwnerId')
        $desiredId = [string] (Get-FabricPropertyValue -InputObject $desiredMetadata -Name 'fpacId')
        if ([string]::IsNullOrWhiteSpace($desiredOwner) -or [string]::IsNullOrWhiteSpace($desiredId)) {
            continue
        }
        $matches = @($aligned.Keys | Where-Object {
            $metadata = Get-FabricPropertyValue -InputObject $aligned[$_] -Name 'metadata'
            [string]::Equals(
                [string] (Get-FabricPropertyValue -InputObject $metadata -Name 'pacOwnerId'),
                $desiredOwner,
                [System.StringComparison]::OrdinalIgnoreCase
            ) -and [string]::Equals(
                [string] (Get-FabricPropertyValue -InputObject $metadata -Name 'fpacId'),
                $desiredId,
                [System.StringComparison]::OrdinalIgnoreCase
            )
        })
        if ($matches.Count -gt 1) {
            throw "More than one deployed Policy Set has FPAC id '$desiredId' for PAC owner '$desiredOwner'."
        }
        if ($matches.Count -eq 1) {
            $deployedArtifact = $aligned[$matches[0]]
            $aligned.Remove($matches[0])
            $deployedArtifact.name = $desiredKey
            $aligned[$desiredKey] = $deployedArtifact
        }
    }
    return $aligned
}
