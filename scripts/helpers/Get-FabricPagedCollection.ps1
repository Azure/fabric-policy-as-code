function Get-FabricPagedCollection {
    param (
        [Parameter(Mandatory)]
        [string] $Uri,

        [Parameter(Mandatory)]
        [hashtable] $Headers
    )

    $results = [System.Collections.Generic.List[object]]::new()
    $nextUri = $Uri
    $seenTokens = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)

    while ($nextUri) {
        $response = Invoke-FabricApiRequest -Method GET -Uri $nextUri -Headers $Headers
        if ($response.StatusCode -ne 200) {
            throw "Expected HTTP 200 when listing Fabric resources; received HTTP $($response.StatusCode) from $nextUri."
        }

        foreach ($entry in @($response.Body.value)) {
            if ($null -ne $entry) {
                $results.Add($entry)
            }
        }

        $continuationToken = [string] (Get-FabricPropertyValue -InputObject $response.Body -Name 'continuationToken')
        if ([string]::IsNullOrWhiteSpace($continuationToken)) {
            $nextUri = $null
            continue
        }
        if (-not $seenTokens.Add($continuationToken)) {
            throw "Fabric returned a repeated continuation token while listing $Uri."
        }

        $separator = if ($Uri.Contains('?')) { '&' } else { '?' }
        $nextUri = "$Uri$separator" + 'continuationToken=' + [Uri]::EscapeDataString($continuationToken)
    }

    return $results.ToArray()
}
