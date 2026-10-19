function Get-WinUtilMemoryCleanerSettings {
    <#
        .SYNOPSIS
            Loads the Memory Cleaner settings, falling back to defaults for anything missing

        .DESCRIPTION
            Unknown areas are dropped, so a hand-edited or older file cannot name an area that
            does not exist. A file that cannot be read is logged and replaced by the defaults.

        .PARAMETER Path
            Settings file. Defaults to memorycleaner.json in the WinUtil folder.
    #>
    param(
        [string]$Path = (Get-WinUtilMemoryCleanerSettingsPath)
    )

    $stored = $null
    if ($Path -and (Test-Path -LiteralPath $Path)) {
        try {
            $stored = Get-Content -LiteralPath $Path -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
        } catch {
            Write-WinUtilLog -Level "WARN" -Component "MemoryCleaner" -Message "Could not read $Path, using default settings: $($_.Exception.Message)"
        }
    }

    return ConvertTo-WinUtilMemoryCleanerSettings -Settings $stored
}

function ConvertTo-WinUtilMemoryCleanerSettings {
    <#
        .SYNOPSIS
            Fills in defaults and drops unknown values of a Memory Cleaner settings object

        .PARAMETER Settings
            Settings as stored or as read from the page. May be $null or partial.
    #>
    param(
        $Settings
    )

    $areas = @(Get-WinUtilMemoryAreas -Build ([int]::MaxValue))
    $known = @($areas | ForEach-Object Key)

    # An empty list is a choice and stays empty; only a missing one means the defaults
    $hasAreas = if ($Settings -is [System.Collections.IDictionary]) {
        $Settings.Contains("Areas")
    } else {
        $null -ne $Settings -and $null -ne $Settings.PSObject.Properties["Areas"]
    }
    if ($hasAreas) {
        $selectedAreas = @($known | Where-Object { @($Settings.Areas) -contains $_ })
    } else {
        $selectedAreas = @($areas | Where-Object Default | ForEach-Object Key)
    }

    return [pscustomobject]@{
        Areas = [string[]]$selectedAreas
    }
}

function Get-WinUtilMemoryCleanerSettingsPath {
    <#
        .SYNOPSIS
            Where the Memory Cleaner settings are kept: memorycleaner.json in the WinUtil folder
    #>

    $directory = if ($null -ne $sync -and $sync.winutildir) { $sync.winutildir } else { Join-Path $env:LocalAppData "winutil" }
    return Join-Path $directory "memorycleaner.json"
}
