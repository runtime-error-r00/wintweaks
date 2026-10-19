function Invoke-WPFTab {

    <#

    .SYNOPSIS
        Sets the selected tab to the tab that was clicked

    .PARAMETER ClickedTab
        The name of the tab that was clicked

    .PARAMETER Yield
        Build the tab's content in slices, letting the interface answer between them. For the
        tab opened at startup, where the window is already on screen and filling in gradually
        reads better than holding the thread until it is complete.

    #>

    Param (
        [Parameter(Mandatory,position=0)]
        [string]$ClickedTab,

        [switch]$Yield
    )

    # Pages are matched by name, not position: WPFTab2BT opens WPFTab2 wherever it sits
    $tabName = $ClickedTab -replace "BT$", ""
    $tabItem = @($sync.WPFTabNav.Items) | Where-Object { $_.Name -eq $tabName } | Select-Object -First 1
    if ($null -eq $tabItem) {
        throw "There is no page named $tabName for $ClickedTab."
    }

    Measure-WinUtilStep -Scope "Tab" -Name "$ClickedTab select" -ScriptBlock {
        $filter = Get-WinUtilVariables -Type ToggleButton | Where-Object {$psitem -like "WPFTab?BT"}
        $tabItem.IsSelected = $true
        ($sync.GetEnumerator()).where{$psitem.Key -in $filter} | ForEach-Object {
            if ($ClickedTab -ne $PSItem.name) {
                $sync[$PSItem.Name].IsChecked = $false
            } else {
                $sync["$ClickedTab"].IsChecked = $true
            }
        }
        $sync.currentTab = $tabItem.Header
    }

    Measure-WinUtilStep -Scope "Tab" -Name "$ClickedTab content" -ScriptBlock {
        Initialize-WinUtilTabContent -TabName $sync.currentTab -Yield:$Yield
    }

    Measure-WinUtilStep -Scope "Tab" -Name "$ClickedTab filter reset" -ScriptBlock {
        $searchText = if ($null -ne $sync.SearchBar) { $sync.SearchBar.Text } else { "" }
        if ($sync.currentTab -eq "Install") {
            Find-AppsByNameOrDescription -SearchString $searchText
        } elseif ($sync.currentTab -eq "Tweaks" -or $sync.currentTab -eq "AppX") {
            Find-TweaksByNameOrDescription -SearchString $searchText
        }
    }

    Measure-WinUtilStep -Scope "Tab" -Name "$ClickedTab search bar" -ScriptBlock {
        # Show search bar in Install, Tweaks, and AppX tabs
        $searchIcon = ($sync.Form.FindName("SearchBar").Parent.Children | Where-Object { $_ -is [System.Windows.Controls.TextBlock] -and $_.Text -eq [char]0xE721 })[0]
        if ($sync.currentTab -in @("Install", "Tweaks", "AppX")) {
            $sync.SearchBar.Visibility = "Visible"
            if ($searchIcon) { $searchIcon.Visibility = "Visible" }
        } else {
            $sync.SearchBar.Visibility = "Collapsed"
            if ($searchIcon) { $searchIcon.Visibility = "Collapsed" }
            $sync.SearchBarClearButton.Visibility = "Collapsed"
        }
    }
}
