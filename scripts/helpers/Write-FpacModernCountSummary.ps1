function Write-FpacModernCountSummary {
    param (
        [Parameter(Mandatory)]
        [string] $Type,

        [Parameter(Mandatory)]
        [int] $Unchanged,

        [Parameter(Mandatory)]
        [int] $TotalChanges,

        [Parameter(Mandatory)]
        [hashtable] $Changes,

        [Parameter()]
        [int] $Indent = 2
    )

    Write-FpacModernSection -Title "$Type Summary"
    if ($Unchanged -gt 0) {
        Write-FpacModernStatus -Message "$Unchanged resources unchanged" -Status info -Indent $Indent
    }
    if ($TotalChanges -eq 0) {
        Write-FpacModernStatus -Message 'No changes required' -Status info -Indent $Indent
        return
    }

    Write-FpacModernStatus -Message "$TotalChanges total changes:" -Status info -Indent $Indent
    if ($Changes.new -gt 0) {
        Write-FpacModernStatus -Message "$($Changes.new) new" -Status success -Indent ($Indent + 2)
    }
    if ($Changes.update -gt 0) {
        Write-FpacModernStatus -Message "$($Changes.update) updates" -Status update -Indent ($Indent + 2)
    }
    if ($Changes.replace -gt 0) {
        Write-FpacModernStatus -Message "$($Changes.replace) replacements" -Status warning -Indent ($Indent + 2)
    }
    if ($Changes.adopt -gt 0) {
        Write-FpacModernStatus -Message "$($Changes.adopt) adoptions" -Status warning -Indent ($Indent + 2)
    }
    if ($Changes.delete -gt 0) {
        Write-FpacModernStatus -Message "$($Changes.delete) deletions" -Status error -Indent ($Indent + 2)
    }
}
