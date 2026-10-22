function Format-FpacOwnershipDescription {
    param (
        [Parameter()]
        [AllowNull()]
        [string] $Description,

        [Parameter(Mandatory, ParameterSetName = 'Ownership')]
        [string] $PacOwnerId,

        [Parameter(Mandatory, ParameterSetName = 'Identity')]
        [switch] $IdentityOnly,

        [Parameter(Mandatory)]
        [string] $FpacId,

        [Parameter()]
        [ValidateRange(1, 10000)]
        [int] $MaxLength = 10000
    )

    if (-not $IdentityOnly -and $PacOwnerId -notmatch '^[A-Za-z0-9._:-]+$') {
        throw "PAC owner id '$PacOwnerId' contains unsupported marker characters."
    }
    if ($FpacId -notmatch '^[A-Za-z0-9._:-]+$') {
        throw "FPAC object id '$FpacId' contains unsupported marker characters."
    }

    $humanDescription = Get-FpacHumanDescription -Description $Description
    $marker = if ($IdentityOnly) { "[[FPAC:v1;id=$FpacId]]" }
    else { "[[FPAC:v1;owner=$PacOwnerId;id=$FpacId]]" }
    $value = if ([string]::IsNullOrWhiteSpace($humanDescription)) {
        $marker
    }
    else {
        "$humanDescription`n`n$marker"
    }
    if ($value.Length -gt $MaxLength) {
        throw "Description plus FPAC marker exceeds the $MaxLength character limit."
    }
    return $value
}
