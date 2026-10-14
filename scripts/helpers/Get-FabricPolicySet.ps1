function Get-FabricPolicySet {
    param (
        [Parameter(Mandatory)]
        [string] $WorkspaceId,

        [Parameter(Mandatory)]
        [string] $PolicySetId,

        [Parameter(Mandatory)]
        [hashtable] $Headers
    )

    $uri = "$script:FabricApiBaseUri/workspaces/$WorkspaceId/policySets/$PolicySetId"
    $response = Invoke-FabricApiRequest -Method GET -Uri $uri -Headers $Headers
    if ($response.StatusCode -ne 200) {
        throw "Fabric Policy Set retrieval for $PolicySetId returned HTTP $($response.StatusCode)."
    }
    return $response.Body
}
