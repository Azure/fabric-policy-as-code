function Write-FpacColoredOutput {
    param (
        [Parameter(Mandatory)]
        [string] $Message,

        [Parameter()]
        [System.ConsoleColor] $Color = [System.ConsoleColor]::White
    )

    if ($null -eq (Get-Variable -Name fpacInfoStream -Scope Global -ErrorAction SilentlyContinue)) {
        $Global:fpacInfoStream = [System.Collections.Generic.List[string]]::new()
    }
    $Global:fpacInfoStream.Add($Message)

    if (Test-FpacCICDEnvironment) {
        $ansiColors = @{
            Black = 30; DarkRed = 31; DarkGreen = 32; DarkYellow = 33
            DarkBlue = 34; DarkMagenta = 35; DarkCyan = 36; Gray = 37
            DarkGray = 90; Red = 91; Green = 92; Yellow = 93
            Blue = 94; Magenta = 95; Cyan = 96; White = 97
        }
        $ansiColor = $ansiColors[$Color.ToString()]
        Write-Host "`e[${ansiColor}m${Message}`e[0m"
        return
    }

    Write-Host $Message -ForegroundColor $Color
}
