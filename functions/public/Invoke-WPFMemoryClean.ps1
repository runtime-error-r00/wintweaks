function Invoke-WPFMemoryClean {
    <#
        .SYNOPSIS
            Cleans the memory areas ticked on the Memory Cleaner page

        .DESCRIPTION
            Saves the ticked areas first, so they are the ones remembered for the next run.
    #>

    $settings = Save-WinUtilMemoryCleanerPage
    if ($null -eq $settings) {
        return
    }
    if (@($settings.Areas).Count -eq 0) {
        Show-WinUtilMessage -Message "Tick at least one area to clean." -Title "Memory Cleaner" -Button "OK" -Icon "Information" | Out-Null
        return
    }

    Start-WinUtilJob -Name "Memory Cleaner" -Parameters @{
        Areas = [string[]]$settings.Areas
    } -ScriptBlock {
        param($Areas)

        $report = Invoke-WinUtilMemoryClean -Areas $Areas

        Invoke-WPFUIThread -Parameters @{
            Title = "Last clean - $(Get-Date -Format 'HH:mm:ss')"
            Lines = [string[]](Format-WinUtilMemoryCleanReport -Report $report)
            Snapshot = $report.After
        } -ScriptBlock {
            param($Title, $Lines, $Snapshot)
            $sync.WPFMemoryReportTitle.Text = $Title
            $sync.WPFMemoryReport.Text = $Lines -join [Environment]::NewLine
            if ($Snapshot) {
                Set-WinUtilMemoryCleanerStats -Snapshot $Snapshot
            }
        }
    }
}
