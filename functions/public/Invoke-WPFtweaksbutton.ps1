function Invoke-WPFtweaksbutton {
  <#

    .SYNOPSIS
        Invokes the functions associated with each group of checkboxes

    .PARAMETER Tweak
        Run these tweaks instead of the checked ones. The Advanced page passes the tweaks of
        the group whose Apply button was pressed.

  #>

  param(
    [string[]]$Tweak
  )

  $Tweaks = if ($Tweak) { @($Tweak) } else { $sync.selectedTweaks }

  if ($Tweaks.count -eq 0) {
    Show-WinUtilMessage -Message "Please check the tweaks you wish to perform." -Title "WinTweaks" -Button "OK" -Icon "Warning"
    return
  }

  # The restore point is offered once for the whole run, when the user commits to it
  $createRestorePoint = Request-WinUtilRestorePoint -Subject "$(@($Tweaks).Count) selected tweak(s)"
  if ($null -eq $createRestorePoint) {
    Write-WinUtilLog -Component "Tweaks" -Message "Tweaks cancelled at the restore point prompt."
    return
  }

  Write-WinUtilLog -Component "Tweaks" -Message "Tweaks requested: $(@($Tweaks).Count) selected tweak(s), restore point: $createRestorePoint"

  Start-WinUtilJob -Name "Tweaks" -Description "Applying tweaks" -Parameters @{
    Tweaks = @($Tweaks)
    CreateRestorePoint = $createRestorePoint
  } -ScriptBlock {
    param($Tweaks, $CreateRestorePoint)

    $tweaksToRun = @($Tweaks)
    $totalSteps = [Math]::Max($tweaksToRun.Count + [int][bool]$CreateRestorePoint, 1)
    $completedSteps = 0

    # The restore point has to be taken before anything else changes
    if ($CreateRestorePoint) {
      Step-WinUtilJob -Status "Creating restore point" -Percent 0
      if (-not (Invoke-WinUtilRestorePointStep -Scope "Tweaks")) {
        return
      }
      $completedSteps = 1
    }

    foreach ($tweak in $tweaksToRun) {
      Step-WinUtilJob -Status "Applying $tweak ($($completedSteps + 1)/$totalSteps)" -Percent ([int](($completedSteps / $totalSteps) * 100))
      Measure-WinUtilStep -Scope "Tweaks" -Name $tweak -ScriptBlock {
        Invoke-WinUtilTweaks $tweak
      }
      $completedSteps++
      Step-WinUtilJob -Percent ([int](($completedSteps / $totalSteps) * 100))
    }
  }
}
