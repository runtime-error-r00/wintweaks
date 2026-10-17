function New-WinUtilRestorePoint {
    <#
    .SYNOPSIS
        Creates a System Restore point before tweaks change the system

    .DESCRIPTION
        Goes through the SystemRestore WMI class rather than Checkpoint-Computer, which does not
        exist in PowerShell 7. System Protection is turned on for the system drive first, since a
        restore point cannot be taken while it is off.

        Windows silently skips a restore point when another one was created in the last 24 hours,
        so the frequency limit is lifted for this call and put back to what it was afterwards.

        Returns $true when the restore point was created and $false otherwise. Never throws, so
        the caller decides whether to carry on without one.

    .PARAMETER Description
        The name the restore point is listed under in System Restore.
    #>
    param(
        [string]$Description = "WinTweaks - before applying tweaks"
    )

    $frequencyKey = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\SystemRestore"
    $frequencyName = "SystemRestorePointCreationFrequency"
    $previousFrequency = (Get-ItemProperty -Path $frequencyKey -Name $frequencyName -ErrorAction SilentlyContinue).$frequencyName

    try {
        Write-WinUtilLog -Component "RestorePoint" -Message "Creating restore point '$Description'."

        $enableResult = Invoke-CimMethod -Namespace "root/default" -ClassName "SystemRestore" -MethodName "Enable" -Arguments @{
            Drive = "$env:SystemDrive\"
        } -ErrorAction Stop
        if ($enableResult.ReturnValue -ne 0) {
            throw "System Protection could not be turned on for $env:SystemDrive (error $($enableResult.ReturnValue))."
        }

        Set-ItemProperty -Path $frequencyKey -Name $frequencyName -Value 0 -Type DWord -ErrorAction Stop

        # 12 = MODIFY_SETTINGS, 100 = BEGIN_SYSTEM_CHANGE
        $createResult = Invoke-CimMethod -Namespace "root/default" -ClassName "SystemRestore" -MethodName "CreateRestorePoint" -Arguments @{
            Description = $Description
            RestorePointType = [uint32]12
            EventType = [uint32]100
        } -ErrorAction Stop
        if ($createResult.ReturnValue -ne 0) {
            throw "Windows returned error $($createResult.ReturnValue)."
        }

        Write-WinUtilLog -Component "RestorePoint" -Message "Restore point created."
        return $true
    } catch {
        Write-WinUtilLog -Level "WARN" -Component "RestorePoint" -Message "The restore point was not created: $($_.Exception.Message)"
        return $false
    } finally {
        if ($null -eq $previousFrequency) {
            Remove-ItemProperty -Path $frequencyKey -Name $frequencyName -ErrorAction SilentlyContinue
        } else {
            Set-ItemProperty -Path $frequencyKey -Name $frequencyName -Value $previousFrequency -Type DWord -ErrorAction SilentlyContinue
        }
    }
}
