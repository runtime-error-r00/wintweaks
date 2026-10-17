function Add-WinUtilCustomApp {
    <#
    .SYNOPSIS
        Adds any winget package to the Install tab by its ID and keeps it for later sessions

    .DESCRIPTION
        The ID is only checked for shape here, not looked up: winget reports an unknown ID when
        the app is installed. A package already in the list, under any category, is not added
        twice.

        Returns $true when the app was added.

    .PARAMETER WingetId
        The winget package ID, for example Mozilla.Firefox.
    #>
    param(
        [string]$WingetId
    )

    $WingetId = ([string]$WingetId).Trim()
    if ($WingetId -notmatch '^[A-Za-z0-9][A-Za-z0-9._+\-]*$') {
        Show-WinUtilMessage -Message "That is not a valid winget ID.`n`nUse the package ID winget shows, for example Mozilla.Firefox. You can look one up with: winget search <name>" -Title "WinTweaks - Custom app" -Button "OK" -Icon "Warning" | Out-Null
        return $false
    }

    if ($sync.InitializedTabs -and $sync.InitializedTabs["Install"] -and -not $sync.InstallAppEntriesRendered) {
        Show-WinUtilMessage -Message "The app list is still loading. Try again in a moment." -Title "WinTweaks - Custom app" -Button "OK" -Icon "Information" | Out-Null
        return $false
    }

    $existing = $sync.configs.applicationsHashtable.GetEnumerator() |
        Where-Object { [string]::Equals([string]$_.Value.winget, $WingetId, [StringComparison]::OrdinalIgnoreCase) } |
        Select-Object -First 1
    if ($existing) {
        Show-WinUtilMessage -Message "$WingetId is already in the list as '$($existing.Value.content)'." -Title "WinTweaks - Custom app" -Button "OK" -Icon "Information" | Out-Null
        return $false
    }

    $customApp = New-WinUtilCustomAppEntry -WingetId $WingetId
    $sync.configs.applicationsHashtable[$customApp.Key] = $customApp.Entry
    Save-WinUtilCustomAppList
    Write-WinUtilLog -Component "CustomApps" -Message "Added custom app $WingetId."

    Update-WinUtilInstallAppList
    return $true
}
