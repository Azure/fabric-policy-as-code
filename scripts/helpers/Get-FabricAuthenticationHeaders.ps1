function Get-FabricAuthenticationHeaders {
    param (
        [Parameter(Mandatory)]
        [string] $TenantId
    )

    if (-not (Get-Command Get-AzAccessToken -ErrorAction SilentlyContinue)) {
        throw 'Az.Accounts is required. Install it with Install-Module Az.Accounts and retry.'
    }

    $context = Get-AzContext
    if (-not $context) {
        if (-not (Get-Command Connect-AzAccount -ErrorAction SilentlyContinue)) {
            throw 'No Az.Accounts sign-in context exists and Connect-AzAccount is unavailable.'
        }
        Connect-AzAccount -Tenant $TenantId | Out-Null
        $context = Get-AzContext
    }

    $contextTenantId = [string] $context.Tenant.Id
    if (-not [string]::Equals($contextTenantId, $TenantId, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "The active Az.Accounts tenant '$contextTenantId' does not match target tenant '$TenantId'. Run Connect-AzAccount -Tenant '$TenantId' and retry."
    }

    $accessToken = Get-AzAccessToken -ResourceUrl 'https://api.fabric.microsoft.com' -AsSecureString
    if ($null -eq $accessToken.Token) {
        throw 'Az.Accounts did not return a Fabric access token.'
    }

    $plainTextToken = ConvertFrom-SecureString -SecureString $accessToken.Token -AsPlainText
    return @{
        Authorization = "$($accessToken.Type) $plainTextToken"
        Accept        = 'application/json'
    }
}
