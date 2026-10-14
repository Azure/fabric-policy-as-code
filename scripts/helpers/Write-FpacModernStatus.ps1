function Write-FpacModernStatus {
    param (
        [Parameter(Mandatory)]
        [string] $Message,

        [Parameter()]
        [ValidateSet('success', 'warning', 'error', 'info', 'skip', 'update', 'processing')]
        [string] $Status = 'info',

        [Parameter()]
        [int] $Indent = 2
    )

    $theme = Get-FpacOutputTheme
    $padding = ' ' * $Indent
    $character = $theme.characters.status[$Status]
    $color = [System.ConsoleColor] $theme.colors.status[$Status]
    Write-FpacColoredOutput -Message "$padding$character $Message" -Color $color
}
