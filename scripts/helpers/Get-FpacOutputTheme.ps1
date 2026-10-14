function Get-FpacOutputTheme {
    return [ordered]@{
        characters = [ordered]@{
            header = [ordered]@{
                topLeft     = '┏'
                topRight    = '┓'
                bottomLeft  = '┗'
                bottomRight = '┛'
                horizontal  = '━'
                vertical    = '┃'
            }
            section = [ordered]@{
                arrow     = '▶'
                underline = '━'
            }
            status = [ordered]@{
                success    = '✓'
                warning    = '⚠'
                error      = '✗'
                info       = '•'
                skip       = '⊘'
                update     = '⭮'
                processing = '↻'
            }
        }
        colors = [ordered]@{
            header = [ordered]@{
                primary   = 'Cyan'
                secondary = 'DarkCyan'
            }
            section = 'Blue'
            status = [ordered]@{
                success    = 'Green'
                warning    = 'Yellow'
                error      = 'Red'
                info       = 'White'
                skip       = 'DarkGray'
                update     = 'Cyan'
                processing = 'Yellow'
            }
        }
    }
}
