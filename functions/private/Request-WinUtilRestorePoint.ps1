function Request-WinUtilRestorePoint {
    <#
    .SYNOPSIS
        Asks whether to take a restore point before a change the user just committed to

    .DESCRIPTION
        Called on the interface thread when the user starts a change, never per checkbox, so the
        question comes up once for the whole run.

        Returns $true for Yes, $false for No and $null for Cancel. With no window, as in a
        headless -Preset or -Config run, there is nobody to ask, so it answers $true: an
        unattended run always takes one.

    .PARAMETER Subject
        What is about to be applied, as it should read in the question.
    #>
    param(
        [Parameter(Mandatory)]
        [string]$Subject
    )

    if (-not (Test-WinUtilUIAlive)) {
        return $true
    }

    $message = "You are about to apply $Subject.`n`n" +
        "Create a System Restore point first? If something goes wrong, you can roll Windows back to it.`n`n" +
        "Yes: create the restore point, then apply.`n" +
        "No: apply without a restore point.`n" +
        "Cancel: go back without changing anything."

    $answer = Show-WinUtilMessage -Message $message -Title "WinTweaks - Restore point" -Button "YesNoCancel" -Icon "Question"

    switch ("$answer") {
        "Yes" { return $true }
        "No" { return $false }
        default { return $null }
    }
}
