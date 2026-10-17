function New-WinUtilCustomAppEntry {
    <#
    .SYNOPSIS
        Builds the Install tab entry for a winget package the user added by its ID

    .DESCRIPTION
        Returns the applicationsHashtable key and the entry, shaped like a catalog entry so the
        install, uninstall and selection code treat it like any other app. The key keeps only
        letters, digits and underscores, since it also names the entry's WPF checkbox.

    .PARAMETER WingetId
        The winget package ID, for example Mozilla.Firefox.
    #>
    param(
        [Parameter(Mandatory)]
        [string]$WingetId
    )

    return [pscustomobject]@{
        Key = "WPFInstallcustom_" + ($WingetId -replace '[^A-Za-z0-9]', '_')
        Entry = [pscustomobject]@{
            category = "Custom"
            choco = "na"
            content = $WingetId
            description = "Custom app you added by its winget ID ($WingetId)."
            link = "https://winstall.app/apps/$WingetId"
            winget = $WingetId
            foss = $false
            custom = $true
        }
    }
}
