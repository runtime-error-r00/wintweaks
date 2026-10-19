function Invoke-WPFundoall {
    <#

    .SYNOPSIS
        Undoes every selected tweak

    .PARAMETER Tab
        Undo only the selected tweaks shown on this page (Tweaks or Advanced).

    #>

    param(
        [ValidateSet("Tweaks", "Advanced")]
        [string]$Tab
    )

    $tweaks = $sync.selectedTweaks
    if ($Tab) {
        $tabTweaks = @((Get-WinUtilTabTweaks -Tab $Tab).PSObject.Properties.Name)
        $tweaks = @($tweaks | Where-Object { $tabTweaks -contains $_ })
    }

    if ($tweaks.count -eq 0) {
        Show-WinUtilMessage -Message "Please check the tweaks you wish to undo." -Title "WinUtil" -Button "OK" -Icon "Warning"
        return
    }

    Start-WinUtilJob -Name "Undo tweaks" -Description "Undoing tweaks" -Parameters @{
        Tweaks = @($tweaks)
    } -ScriptBlock {
        param($Tweaks)

        $total = @($Tweaks).Count
        Write-WinUtilLog -Component "Tweaks" -Message "Undo tweaks requested: $total selected tweak(s)."

        for ($i = 0; $i -lt $total; $i++) {
            Step-WinUtilJob -Status "Undoing $($Tweaks[$i]) ($($i + 1)/$total)" -Percent ([int](($i / $total) * 100))
            Measure-WinUtilStep -Scope "Undo tweaks" -Name $Tweaks[$i] -ScriptBlock {
                Invoke-WinUtiltweaks $Tweaks[$i] -undo $true
            }
            Step-WinUtilJob -Percent ([int]((($i + 1) / $total) * 100))
        }
    }
}
