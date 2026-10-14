function Format-FpacOwnershipDescription {
    param (
        [Parameter()]
        [AllowNull()]
        [string] $Description,

        [Parameter(Mandatory)]
        [string] $PacOwnerId,

        [Parameter(Mandatory)]
        [string] $FpacId,

        [Parameter()]
        [ValidateRange(1, 10000)]
        [int] $MaxLength = 10000
    )

    if ($PacOwnerId -notmatch '^[A-Za-z0-9._:-]+$') {
        throw "PAC owner id '$PacOwnerId' contains unsupported marker characters."
    }
    if ($FpacId -notmatch '^[A-Za-z0-9._:-]+$') {
        throw "FPAC object id '$FpacId' contains unsupported marker characters."
    }

    $humanDescription = Get-FpacHumanDescription -Description $Description
    $marker = "[[FPAC:v1;owner=$PacOwnerId;id=$FpacId]]"
    $value = if ([string]::IsNullOrWhiteSpace($humanDescription)) {
        $marker
    }
    else {
        "$humanDescription`n`n$marker"
    }
    if ($value.Length -gt $MaxLength) {
        throw "Description plus FPAC ownership marker exceeds the $MaxLength character limit."
    }
    return $value
}
