function Invoke-WPFAdvancedGroup {
    <#

    .SYNOPSIS
        Opens one optimization group of the Advanced page, or goes back to its menu

    .PARAMETER Group
        General, KeyboardMouse, GPU or CPU. Without it the menu is shown again.

    #>
    param(
        [ValidateSet("General", "KeyboardMouse", "GPU", "CPU")]
        [string]$Group
    )

    if (-not $Group) {
        $sync.AdvancedGroup = $null
        $sync.WPFAdvancedDetail.Visibility = "Collapsed"
        $sync.WPFAdvancedMenu.Visibility = "Visible"
        return
    }

    $definition = Get-WinUtilAdvancedGroup -Group $Group
    $sync.AdvancedGroup = $Group

    $description = $definition.Description
    if ($Group -eq "GPU") {
        $found = @("NVIDIA", "AMD", "Intel" | Where-Object { @(Get-WinUtilDisplayAdapterKey -Vendor $_).Count -gt 0 })
        $description += if ($found.Count -gt 0) { " Graphics found: $($found -join ', ')." } else { " No NVIDIA, AMD or Intel graphics found." }
    }

    $sync.WPFAdvancedDetailTitle.Text = $definition.Title
    $sync.WPFAdvancedDetailDescription.Text = $description

    $sync.WPFAdvancedDetailList.Children.Clear()
    foreach ($tweak in $definition.Tweaks) {
        $entry = $sync.configs.tweaks.$tweak
        $line = New-Object Windows.Controls.TextBlock
        $line.Text = [string][char]0x2022 + " " + $entry.Content
        $line.ToolTip = $entry.Description
        $line.TextWrapping = "Wrap"
        $line.Margin = "0,2,0,2"
        $line.SetResourceReference([Windows.Controls.TextBlock]::ForegroundProperty, "MainForegroundColor")
        $sync.WPFAdvancedDetailList.Children.Add($line) | Out-Null
    }

    $sync.advancedqueuepanel.Visibility = if ($Group -eq "KeyboardMouse") { "Visible" } else { "Collapsed" }
    $sync.WPFAdvancedCoreIsolationPanel.Visibility = if ($Group -eq "General") { "Visible" } else { "Collapsed" }

    $sync.WPFAdvancedMenu.Visibility = "Collapsed"
    $sync.WPFAdvancedDetail.Visibility = "Visible"
}
