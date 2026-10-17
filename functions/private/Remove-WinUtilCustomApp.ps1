function Remove-WinUtilCustomApp {
    <#
    .SYNOPSIS
        Takes a custom winget app off the Install tab list, for this and later sessions

    .DESCRIPTION
        Only entries the user added can be removed; catalog apps are left alone. Removing an app
        from the list does not uninstall it.

    .PARAMETER AppKey
        The entry's key in $sync.configs.applicationsHashtable.
    #>
    param(
        [Parameter(Mandatory)]
        [string]$AppKey
    )

    $entry = $sync.configs.applicationsHashtable[$AppKey]
    if ($null -eq $entry -or $entry.custom -ne $true) {
        return
    }

    $sync.configs.applicationsHashtable.Remove($AppKey)
    if ($sync.selectedApps -contains $AppKey) {
        Invoke-WPFSelectedCheckboxesUpdate -type "Remove" -checkboxName $AppKey
    }
    Save-WinUtilCustomAppList
    Write-WinUtilLog -Component "CustomApps" -Message "Removed custom app $($entry.winget) from the list."

    Update-WinUtilInstallAppList
}
