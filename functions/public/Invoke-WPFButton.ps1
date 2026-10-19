function Invoke-WPFButton {

    <#

    .SYNOPSIS
        Routes a button press, deciding whether it is interface work or a job

    .DESCRIPTION
        This is the one place that classifies a button. Anything that changes the system runs
        through Start-WinUtilJob, which means it gets the busy flag, the progress bar, the
        taskbar item, the console banner and the log lines without each workflow arranging that
        for itself. Anything that only changes what the interface is showing runs here and now,
        because pushing it onto a worker would just make it slower.

    .PARAMETER Button
        The name of the button that was clicked

    #>

    Param ([string]$Button)

    # Clear the progress left behind by the previous job, but never while one is running
    if (-not $sync.ActiveJob) {
        Step-WinUtilJob -Hide
    }

    # Switch-driven buttons that change the system.
    #
    # This is a whitelist on purpose: window chrome and popup toggles also reach here, because
    # every Button in $sync gets wired to this function, and they must not become jobs.
    $workButtons = @(
        "WPFInstallUpgrade",
        "WPFUpdatesdefault", "WPFUpdatessecurity",
        "WPFGetInstalledAppx"
    )

    if ($workButtons -contains $Button) {
        # The Recommended update profile replaces system policy, so like the tweaks it offers a
        # restore point once, before the job starts
        $createRestorePoint = $false
        if ($Button -eq "WPFUpdatessecurity") {
            $createRestorePoint = Request-WinUtilRestorePoint -Subject "the Recommended Windows Update profile"
            if ($null -eq $createRestorePoint) {
                Write-WinUtilLog -Component "Updates" -Message "Recommended update profile cancelled at the restore point prompt."
                return
            }
        }

        Start-WinUtilJob -Name (Get-WinUtilButtonLabel -Button $Button) -Parameters @{
            Button = $Button
            CreateRestorePoint = $createRestorePoint
        } -ScriptBlock {
            param($Button, $CreateRestorePoint)

            if ($CreateRestorePoint) {
                Step-WinUtilJob -Status "Creating restore point" -Percent 0
                if (-not (Invoke-WinUtilRestorePointStep -Scope "Updates")) {
                    return
                }
            }

            Invoke-WPFButtonAction -Button $Button
        }
        return
    }

    # A handler that throws on the interface thread would otherwise reach the user as a bare
    # message with no indication of which control produced it
    try {
        Invoke-WPFButtonAction -Button $Button
    } catch {
        Write-WinUtilErrorRecord -ErrorRecord $_ -Component "UI" -Context "Button '$Button'"
    }
}

function Get-WinUtilButtonLabel {
    <#
    .SYNOPSIS
        Returns the name a button's job should be reported under.

    .DESCRIPTION
        Whatever the button says is what the progress bar, the banner and the log say, so the
        wording never drifts from the interface and there is no second list to maintain. Falls
        back to the button name when there is nothing to read.
    #>
    param([string]$Button)

    $control = $sync.$Button
    if ($control -and $control.Content) {
        $text = if ($control.Content -is [string]) { $control.Content } else { $control.Content.Text }
        if (-not [string]::IsNullOrWhiteSpace($text)) {
            return ([string]$text).Trim()
        }
    }

    $fallback = ($Button -replace '^WPF', '')
    if ([string]::IsNullOrWhiteSpace($fallback)) {
        return "WinUtil"
    }
    return $fallback
}

function Invoke-WPFButtonAction {

    <#

    .SYNOPSIS
        Invokes the function associated with the clicked button

    .DESCRIPTION
        The work itself. Called by Invoke-WPFButton, either directly or from inside a job, so it
        must not concern itself with progress, busy state or banners.

    .PARAMETER Button
        The name of the button that was clicked

    #>

    Param (
        [string]$Button
    )

    Switch -Wildcard ($Button) {
        "WPFTab?BT" {Invoke-WPFTab $Button}
        "WPFInstall" {Invoke-WPFInstall}
        "WPFUninstall" {Invoke-WPFUnInstall}
        "WPFInstallUpgrade" {Invoke-WPFInstallUpgrade}
        "WPFCollapseAllCategories" {Invoke-WPFToggleAllCategories -Action "Collapse"}
        "WPFExpandAllCategories" {Invoke-WPFToggleAllCategories -Action "Expand"}
        "WPFStandard" {Invoke-WPFPresets "Standard" -checkboxfilterpattern "WPFTweak*"}
        "WPFMinimal" {Invoke-WPFPresets "Minimal" -checkboxfilterpattern "WPFTweak*"}
        "WPFAdvanced" {Invoke-WPFPresets "Advanced" -checkboxfilterpattern "WPFTweak*"}
        "WPFClearTweaksSelection" {Invoke-WPFPresets -imported $true -checkboxfilterpattern "WPFTweak*"}
        "WPFClearInstallSelection" {Invoke-WPFPresets -imported $true -checkboxfilterpattern "WPFInstall*"}
        "WPFSelectNewPCKit" {Invoke-WPFPresets "NewPCKit" -checkboxfilterpattern "WPFInstall*"}
        "WPFtweaksbutton" {Invoke-WPFtweaksbutton -Tab "Tweaks"}
        "WPFundoall" {Invoke-WPFundoall -Tab "Tweaks"}
        "WPFAdvancedTweaksbutton" {Invoke-WPFtweaksbutton -Tab "Advanced"}
        "WPFAdvancedUndo" {Invoke-WPFundoall -Tab "Advanced"}
        "WPFClearAdvancedSelection" {
            (Get-WinUtilTabTweaks -Tab "Advanced").PSObject.Properties.Name |
                Where-Object { $sync[$_] -is [System.Windows.Controls.CheckBox] } |
                ForEach-Object { $sync[$_].IsChecked = $false }
        }
        "WPFUpdatesdefault" {Invoke-WPFUpdatesdefault}
        "WPFUpdatessecurity" {Invoke-WPFUpdatessecurity}
        "WPFGetInstalled" {Invoke-WPFGetInstalled -CheckBox "winget"}
        "WPFGetInstalledTweaks" {Invoke-WPFGetInstalled -CheckBox "tweaks"}
        "WPFAppxRemoval" {Invoke-WPFTab "WPFTab6BT"}
        "WPFBackToTweaks" {Invoke-WPFTab "WPFTab2BT"}
        "WPFInstallSelectedAppx" {Invoke-WPFAppxInstall}
        "WPFRemoveSelectedAppx" {Invoke-WPFAppxRemoval}
        "WPFDefaultAppxSelection" {Invoke-WPFPresets "AppxDefault" -checkboxfilterpattern "WPFAppx*"}
        "WPFSelectAllAppx" {
            $sync.configs.appxHashtable.Keys | ForEach-Object {$sync.$_.IsChecked = $true}
        }
        "WPFClearAppxSelection" {
            $sync.configs.appxHashtable.Keys | ForEach-Object {$sync.$_.IsChecked = $false}
        }
        "WPFGetInstalledAppx" {
            $installedAppxPackages = Get-WinUtilInstalledAPPX
            Invoke-WPFUIThread -Parameters @{ Installed = $installedAppxPackages } -ScriptBlock {
                param($Installed)
                foreach ($appx in $sync.configs.appxHashtable.GetEnumerator()) {
                    if ($appx.Value.PackageId -in $Installed) {
                        $sync.$($appx.Key).IsChecked = $true
                    }
                }
            }
        }
        # Closing may be declined, or leave a job running that outlives the window, so the
        # goodbye belongs at the point the process actually ends rather than here
        "WPFCloseButton" {$sync.Form.Close()}
        "WPFMinimizeButton" {[Windows.SystemCommands]::MinimizeWindow($sync.Form)}
        "WPFMaximizeButton" {
            if ($sync.Form.WindowState -eq [Windows.WindowState]::Normal) {
                [Windows.SystemCommands]::MaximizeWindow($sync.Form)
            } else {
                [Windows.SystemCommands]::RestoreWindow($sync.Form)
            }
        }
        "WPFselectedAppsButton" {$sync.selectedAppsPopup.IsOpen = -not $sync.selectedAppsPopup.IsOpen}
    }
}
