function Initialize-WinUtilMemoryCleanerPage {
    <#
        .SYNOPSIS
            Fills the Memory Cleaner page from the saved settings and starts reading memory use

        .DESCRIPTION
            Areas the running Windows build does not support are greyed out and unticked, with
            the reason in their tooltip.
    #>

    if ($null -eq $sync.MemoryCleanerSettings) {
        $sync.MemoryCleanerSettings = Get-WinUtilMemoryCleanerSettings
    }
    Set-WinUtilMemoryCleanerPage -Settings $sync.MemoryCleanerSettings

    foreach ($area in (Get-WinUtilMemoryAreas)) {
        $checkBox = $sync["WPFMemoryArea$($area.Key)"]
        if ($null -eq $checkBox) { continue }
        $checkBox.ToolTip = $area.Description
        if (-not $area.Supported) {
            $checkBox.IsChecked = $false
            $checkBox.IsEnabled = $false
            $checkBox.ToolTip = "Needs Windows build $($area.MinimumBuild) or later."
        }
    }

    Update-WinUtilMemoryCleanerView
}

function Set-WinUtilMemoryCleanerPage {
    <#
        .SYNOPSIS
            Shows Memory Cleaner settings in the page's controls
    #>
    param(
        [Parameter(Mandatory)]
        $Settings
    )

    foreach ($area in (Get-WinUtilMemoryAreas)) {
        $checkBox = $sync["WPFMemoryArea$($area.Key)"]
        if ($null -ne $checkBox -and $checkBox.IsEnabled) {
            $checkBox.IsChecked = @($Settings.Areas) -contains $area.Key
        }
    }
}

function Save-WinUtilMemoryCleanerPage {
    <#
        .SYNOPSIS
            Reads the page, saves it and puts the validated values back on the page

        .OUTPUTS
            The saved settings, or $null when they could not be written.
    #>

    $areas = foreach ($area in (Get-WinUtilMemoryAreas)) {
        $checkBox = $sync["WPFMemoryArea$($area.Key)"]
        if ($null -ne $checkBox -and $checkBox.IsEnabled -and $checkBox.IsChecked) { $area.Key }
    }

    $fromPage = [pscustomobject]@{
        Areas = @($areas)
    }

    try {
        $saved = Save-WinUtilMemoryCleanerSettings -Settings $fromPage
    } catch {
        Write-WinUtilErrorRecord -ErrorRecord $_ -Component "MemoryCleaner" -Context "Saving settings"
        Show-WinUtilMessage -Message "The Memory Cleaner settings could not be saved: $($_.Exception.Message)" -Title "Memory Cleaner" -Button "OK" -Icon "Error" | Out-Null
        return $null
    }

    $sync.MemoryCleanerSettings = $saved
    Set-WinUtilMemoryCleanerPage -Settings $saved
    return $saved
}

function Update-WinUtilMemoryCleanerView {
    <#
        .SYNOPSIS
            Reads memory use on a worker and shows it on the page

        .DESCRIPTION
            The first read compiles the native helpers, which takes long enough to be felt on
            the interface thread.
    #>

    $null = Invoke-WPFRunspace -ScriptBlock {
        try {
            $snapshot = Get-WinUtilMemorySnapshot
            Invoke-WPFUIThread -Async -Parameters @{ Snapshot = $snapshot } -ScriptBlock {
                param($Snapshot)
                Set-WinUtilMemoryCleanerStats -Snapshot $Snapshot
            }
        } catch {
            Write-WinUtilErrorRecord -ErrorRecord $_ -Component "MemoryCleaner" -Context "Reading memory use"
        }
    }
}

function Set-WinUtilMemoryCleanerStats {
    <#
        .SYNOPSIS
            Shows a memory snapshot in the figures at the top of the Memory Cleaner page
    #>
    param(
        [Parameter(Mandatory)]
        $Snapshot
    )

    $sync.WPFMemoryUsed.Text = "$(Format-WinUtilMemorySize $Snapshot.UsedBytes) ($($Snapshot.LoadPercent)%)"
    $sync.WPFMemoryAvailable.Text = Format-WinUtilMemorySize $Snapshot.AvailableBytes
    $sync.WPFMemoryTotal.Text = Format-WinUtilMemorySize $Snapshot.TotalBytes
    $sync.WPFMemoryFree.Text = Format-WinUtilMemorySize $Snapshot.FreeBytes
    $sync.WPFMemoryStandby.Text = Format-WinUtilMemorySize $Snapshot.StandbyBytes
    $sync.WPFMemoryModified.Text = Format-WinUtilMemorySize $Snapshot.ModifiedBytes
}
