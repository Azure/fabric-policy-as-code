function Remove-FabricPolicySet {
    param (
        [Parameter(Mandatory)]
        [object] $PolicySet,

        [Parameter(Mandatory)]
        [object] $ResolvedItem,

        [Parameter(Mandatory)]
        [hashtable] $Headers,

        [Parameter()]
        [switch] $SkipDeactivation
    )

    if (-not $SkipDeactivation -and [string] $PolicySet.properties.status -eq 'Active') {
        Set-FabricPolicySetStatus -WorkspaceId $ResolvedItem.WorkspaceId `
            -PolicySetId $ResolvedItem.PolicySetId `
            -Scope $PolicySet.properties.scope `
            -DesiredStatus 'Inactive' `
            -CurrentStatus 'Active' `
            -Headers $Headers
    }

    $uri = "$script:FabricApiBaseUri/workspaces/$($ResolvedItem.WorkspaceId)/policySets/$($ResolvedItem.PolicySetId)"
    $response = Invoke-FabricApiRequest -Method DELETE -Uri $uri -Headers $Headers
    if ($response.StatusCode -ne 200) {
        throw "Fabric Policy Set deletion returned HTTP $($response.StatusCode)."
    }
}
