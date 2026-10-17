function Invoke-WinUtilRestorePointStep {
    <#
    .SYNOPSIS
        Takes the restore point at the start of a job and decides whether the job may go on

    .DESCRIPTION
        Runs inside a job body, before anything changes. The user asked for a restore point, so
        when it cannot be created they are asked whether to carry on without one. A headless run
        has nobody to ask and carries on with a warning in the log.

        Returns $true when the job should continue.

    .PARAMETER Scope
        The job the restore point belongs to, used for the log and the timing summary.
    #>
    param(
        [string]$Scope = "Tweaks"
    )

    $created = Measure-WinUtilStep -Scope $Scope -Name "Restore point" -ScriptBlock {
        New-WinUtilRestorePoint
    }
    if (@($created)[-1] -eq $true) {
        return $true
    }

    if (-not (Test-WinUtilUIAlive)) {
        Write-WinUtilLog -Level "WARN" -Component $Scope -Message "Continuing without a restore point, there is nobody to ask in a headless run."
        return $true
    }

    $message = "The restore point could not be created. The log has the reason.`n`n" +
        "Apply the changes anyway, without a restore point?"
    $answer = Show-WinUtilMessage -Message $message -Title "WinTweaks - Restore point" -Button "YesNo" -Icon "Warning"

    if ("$answer" -eq "Yes") {
        Write-WinUtilLog -Level "WARN" -Component $Scope -Message "Continuing without a restore point at the user's request."
        return $true
    }

    Write-WinUtilLog -Component $Scope -Message "Stopped before any change because the restore point could not be created."
    return $false
}
