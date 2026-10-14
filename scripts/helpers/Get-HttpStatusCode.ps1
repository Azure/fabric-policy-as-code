function Get-HttpStatusCode {
    param (
        [Parameter()]
        [System.Management.Automation.ErrorRecord] $ErrorRecord
    )

    $responseProperty = $ErrorRecord.Exception.PSObject.Properties['Response']
    if ($null -eq $responseProperty) {
        return 0
    }

    $response = $responseProperty.Value
    if ($null -ne $response -and $null -ne $response.StatusCode) {
        return [int] $response.StatusCode
    }

    return 0
}
