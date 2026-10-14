function Write-FpacModernSection {
    param (
        [Parameter(Mandatory)]
        [string] $Title,

        [Parameter()]
        [int] $Indent = 0,

        [Parameter()]
        [System.ConsoleColor] $Color = [System.ConsoleColor]::Blue
    )

    $theme = Get-FpacOutputTheme
    $padding = ' ' * $Indent
    Write-Host
    Write-FpacColoredOutput -Message "$padding$($theme.characters.section.arrow) $Title" -Color $Color
    Write-FpacColoredOutput -Message "$padding$($theme.characters.section.underline * ($Title.Length + 2))" -Color $Color
}
