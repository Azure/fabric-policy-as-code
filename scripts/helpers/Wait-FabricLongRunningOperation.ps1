function Wait-FabricLongRunningOperation {
    param (
        [Parameter(Mandatory)]
        [object] $Response,

        [Parameter(Mandatory)]
        [hashtable] $Headers,

        [Parameter()]
        [ValidateRange(1, 7200)]
        [int] $TimeoutSeconds = 1800
    )

    if ($Response.StatusCode -ne 202) {
        return $Response.Body
    }

    $operationUri = [string] (Get-ResponseHeaderValue -Headers $Response.Headers -Name 'Location')
    if ([string]::IsNullOrWhiteSpace($operationUri)) {
        $operationId = [string] (Get-ResponseHeaderValue -Headers $Response.Headers -Name 'x-ms-operation-id')
        if ([string]::IsNullOrWhiteSpace($operationId)) {
            throw 'Fabric returned HTTP 202 without a Location or x-ms-operation-id header.'
        }
        $operationUri = "$script:FabricApiBaseUri/operations/$operationId"
    }

    $timer = [System.Diagnostics.Stopwatch]::StartNew()
    while ($timer.Elapsed.TotalSeconds -lt $TimeoutSeconds) {
        $retryAfter = Get-ResponseHeaderValue -Headers $Response.Headers -Name 'Retry-After'
        $delaySeconds = if ([string] $retryAfter -match '^\d+$') {
            [Math]::Max(1, [int] $retryAfter)
        }
        else {
            5
        }
        Start-Sleep -Seconds $delaySeconds

        $Response = Invoke-FabricApiRequest -Method GET -Uri $operationUri -Headers $Headers
        if ($Response.StatusCode -ne 200) {
            throw "Fabric operation polling returned HTTP $($Response.StatusCode)."
        }
        $status = [string] (Get-FabricPropertyValue -InputObject $Response.Body -Name 'status')
        switch ($status) {
            'Succeeded' {
                return $Response.Body
            }
            'Failed' {
                $error = Get-FabricPropertyValue -InputObject $Response.Body -Name 'error'
                $message = [string] (Get-FabricPropertyValue -InputObject $error -Name 'message')
                if ([string]::IsNullOrWhiteSpace($message)) {
                    $message = 'Fabric reported that the operation failed.'
                }
                throw $message
            }
            'Cancelled' {
                throw 'Fabric reported that the operation was cancelled.'
            }
        }
    }

    throw "Fabric operation did not complete within $TimeoutSeconds seconds."
}
