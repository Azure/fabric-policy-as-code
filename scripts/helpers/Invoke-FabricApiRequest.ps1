function Invoke-FabricApiRequest {
    param (
        [Parameter(Mandatory)]
        [ValidateSet('GET', 'POST', 'PATCH', 'DELETE')]
        [string] $Method,

        [Parameter(Mandatory)]
        [string] $Uri,

        [Parameter(Mandatory)]
        [hashtable] $Headers,

        [Parameter()]
        [AllowNull()]
        [object] $Body
    )

    for ($attempt = 1; $attempt -le $MaxRetryAttempts; $attempt++) {
        $statusCode = 0
        $responseHeaders = $null
        try {
            $request = @{
                Method                  = $Method
                Uri                     = $Uri
                Headers                 = $Headers
                HttpVersion             = '1.1'
                StatusCodeVariable      = 'statusCode'
                ResponseHeadersVariable = 'responseHeaders'
                ErrorAction             = 'Stop'
            }
            if ($PSBoundParameters.ContainsKey('Body')) {
                $request.Body = if ($Body -is [string]) {
                    $Body
                }
                else {
                    $Body | ConvertTo-Json -Depth 100 -Compress
                }
                $request.ContentType = 'application/json'
            }
            $responseBody = Invoke-RestMethod @request

            return [pscustomobject]@{
                StatusCode = [int] $statusCode
                Headers    = $responseHeaders
                Body       = $responseBody
            }
        }
        catch {
            $httpStatusCode = Get-HttpStatusCode -ErrorRecord $_
            $isRetryable = $httpStatusCode -in @(429, 500, 502, 503, 504) -or
                ($httpStatusCode -eq 0 -and (Test-FabricTransientTransportFailure -ErrorRecord $_))
            if (-not $isRetryable -or $attempt -ge $MaxRetryAttempts) {
                $details = $_.ErrorDetails.Message
                if ([string]::IsNullOrWhiteSpace($details)) {
                    $details = $_.Exception.Message
                }
                throw "Fabric API $Method $Uri failed (HTTP $httpStatusCode): $details"
            }

            $responseProperty = $_.Exception.PSObject.Properties['Response']
            $errorHeaders = if ($null -ne $responseProperty) {
                $responseProperty.Value.Headers
            }
            else {
                $null
            }
            $retryAfter = Get-ResponseHeaderValue -Headers $errorHeaders -Name 'Retry-After'
            $delaySeconds = 2 * $attempt
            if ($retryAfter -match '^\d+$') {
                $delaySeconds = [Math]::Max(1, [int] $retryAfter)
            }
            Start-Sleep -Seconds $delaySeconds
        }
    }
}
