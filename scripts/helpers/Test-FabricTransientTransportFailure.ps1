function Test-FabricTransientTransportFailure {
    param (
        [Parameter(Mandatory)]
        [System.Management.Automation.ErrorRecord] $ErrorRecord
    )

    $exception = $ErrorRecord.Exception
    while ($null -ne $exception) {
        if ($exception -is [System.Net.Http.HttpRequestException] -or
            $exception -is [System.IO.IOException] -or
            $exception -is [System.Net.Sockets.SocketException] -or
            $exception -is [System.Net.WebException]) {
            return $true
        }
        $exception = $exception.InnerException
    }

    return $false
}
