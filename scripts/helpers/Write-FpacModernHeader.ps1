function Write-FpacModernHeader {
    param (
        [Parameter(Mandatory)]
        [string] $Title,

        [Parameter()]
        [string] $Subtitle,

        [Parameter()]
        [System.ConsoleColor] $HeaderColor = [System.ConsoleColor]::Cyan,

        [Parameter()]
        [System.ConsoleColor] $SubtitleColor = [System.ConsoleColor]::DarkCyan
    )

    $theme = Get-FpacOutputTheme
    $width = [Math]::Max($Title.Length, $Subtitle.Length) + 4
    $horizontal = [string] $theme.characters.header.horizontal
    Write-Host
    Write-FpacColoredOutput -Message "$($theme.characters.header.topLeft)$($horizontal * ($width - 2))$($theme.characters.header.topRight)" -Color $HeaderColor
    Write-FpacColoredOutput -Message "$($theme.characters.header.vertical) $($Title.PadRight($width - 4)) $($theme.characters.header.vertical)" -Color $HeaderColor
    if (-not [string]::IsNullOrWhiteSpace($Subtitle)) {
        Write-FpacColoredOutput -Message "$($theme.characters.header.vertical) $($Subtitle.PadRight($width - 4)) $($theme.characters.header.vertical)" -Color $SubtitleColor
    }
    Write-FpacColoredOutput -Message "$($theme.characters.header.bottomLeft)$($horizontal * ($width - 2))$($theme.characters.header.bottomRight)" -Color $HeaderColor
    Write-Host
}
