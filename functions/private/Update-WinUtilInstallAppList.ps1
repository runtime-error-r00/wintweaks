function Update-WinUtilInstallAppList {
    <#
    .SYNOPSIS
        Redraws the Install tab app list after the catalog changed

    .DESCRIPTION
        Before the Install tab is first built there is nothing to redraw: it reads the catalog
        when it is built. Selected apps stay selected, because each entry reads the selection
        when it is drawn.
    #>

    if (-not $sync.InitializedTabs -or -not $sync.InitializedTabs["Install"] -or $null -eq $sync.ItemsControl) {
        return
    }

    $sync.ItemsControl.Items.Clear()
    Initialize-InstallCategoryAppList -TargetElement $sync.ItemsControl -Apps $sync.configs.applicationsHashtable
}
