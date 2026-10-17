function Import-WinUtilCustomAppList {
    <#
    .SYNOPSIS
        Adds the custom winget apps saved in an earlier session to the app catalog

    .DESCRIPTION
        Reads custom-apps.json from the WinTweaks data folder, a plain list of winget IDs, and
        puts each one into $sync.configs.applicationsHashtable under the Custom category. A
        missing or unreadable file leaves the catalog as it is.
    #>

    $path = Join-Path $sync.winutildir "custom-apps.json"
    if (-not (Test-Path -LiteralPath $path)) {
        return
    }

    try {
        # Assigned rather than wrapped in @(): Windows PowerShell's ConvertFrom-Json hands back a
        # JSON array as one object, which @() would nest instead of unrolling
        $wingetIds = Get-Content -LiteralPath $path -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
    } catch {
        Write-WinUtilLog -Level "WARN" -Component "CustomApps" -Message "Ignoring unreadable $path : $($_.Exception.Message)"
        return
    }

    foreach ($wingetId in @($wingetIds)) {
        if ([string]::IsNullOrWhiteSpace([string]$wingetId)) {
            continue
        }
        $customApp = New-WinUtilCustomAppEntry -WingetId ([string]$wingetId)
        $sync.configs.applicationsHashtable[$customApp.Key] = $customApp.Entry
    }
}
