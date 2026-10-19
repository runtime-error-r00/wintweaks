function Save-WinUtilMemoryCleanerSettings {
    <#
        .SYNOPSIS
            Validates the Memory Cleaner settings, writes them to disk and returns what was saved

        .PARAMETER Settings
            Settings to store. Passed through ConvertTo-WinUtilMemoryCleanerSettings first, so
            the file only ever holds known areas.

        .PARAMETER Path
            Settings file. Defaults to memorycleaner.json in the WinUtil folder.
    #>
    param(
        [Parameter(Mandatory)]
        $Settings,

        [string]$Path = (Get-WinUtilMemoryCleanerSettingsPath)
    )

    $validated = ConvertTo-WinUtilMemoryCleanerSettings -Settings $Settings

    $directory = Split-Path -Path $Path -Parent
    if ($directory -and -not (Test-Path -LiteralPath $directory)) {
        New-Item -ItemType Directory -Path $directory -Force | Out-Null
    }
    $validated | ConvertTo-Json -Depth 3 | Set-Content -LiteralPath $Path -Encoding UTF8

    return $validated
}
