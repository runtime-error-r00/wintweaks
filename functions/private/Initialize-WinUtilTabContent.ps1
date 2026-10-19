function Initialize-WinUtilTabContent {
    param(
        [Parameter(Mandatory = $true)]
        [string]$TabName,

        # Build in batches, letting the interface answer in between. Used by the warmup, which
        # nobody is waiting on. A tab the user just clicked is built in one go.
        [switch]$Yield
    )

    if ($null -eq $sync.InitializedTabs) {
        $sync.InitializedTabs = @{}
    }

    if ($sync.InitializedTabs[$TabName]) {
        return
    }

    # Claimed before building, not after: a yielding build lets a click through, and that click
    # would otherwise start building the same tab a second time.
    $sync.InitializedTabs[$TabName] = $true

    try {
        switch ($TabName) {
            "Install" {
                Measure-WinUtilStep -Scope "UI" -Name "Install tab: category area" -ScriptBlock {
                    Initialize-WPFUI -targetGridName "appscategory"
                }
                Measure-WinUtilStep -Scope "UI" -Name "Install tab: app area" -ScriptBlock {
                    Initialize-WPFUI -targetGridName "appspanel"
                }
                Initialize-WinUtilInstallTabControls
            }
            "Tweaks" {
                Invoke-WPFUIElements -configVariable (Get-WinUtilTabTweaks -Tab "Tweaks") -targetGridName "tweakspanel" -columncount 2 -Yield:$Yield
            }
            "Advanced" {
                Invoke-WPFUIElements -configVariable (Get-WinUtilTabTweaks -Tab "Advanced") -targetGridName "advancedpanel" -columncount 2 -Yield:$Yield
            }
            "AppX" {
                Invoke-WPFUIElements -configVariable $sync.configs.appx -targetGridName "appxpanel" -columncount 2 -Yield:$Yield
            }
        }
        # Controls built just now start unchecked, so anything already chosen by an import or a
        # preset has to be applied to them once they exist
        Reset-WPFCheckBoxes -doToggles $true
    } catch {
        # A half built tab must be allowed to rebuild rather than staying empty forever
        $sync.InitializedTabs[$TabName] = $false
        throw
    }
}
