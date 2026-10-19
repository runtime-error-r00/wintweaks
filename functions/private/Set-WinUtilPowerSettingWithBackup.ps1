function Set-WinUtilPowerSettingWithBackup {
    <#

    .SYNOPSIS
        Changes settings of the active power plan, keeping their previous values for undo

    .DESCRIPTION
        The previous mains (AC) and battery (DC) values are read with powercfg /qh, which also
        lists hidden settings, and recorded under HKLM:\SOFTWARE\WinTweaks\Backup\<Name> together
        with the plan they belong to. -Undo writes them back to that same plan.

        powercfg prints localized labels, so only the last two hexadecimal values of its output
        are read: they are always the current AC and DC index.

    .PARAMETER Name
        The backup name, one per tweak.

    .PARAMETER Settings
        Hashtables with SubGroup, Setting and AC, plus DC when the battery value changes too.

    .PARAMETER Undo
        Restore the recorded values and delete the backup.

    .PARAMETER BackupKey
        Where the previous values are recorded. Only tests point it elsewhere.

    .EXAMPLE
        Set-WinUtilPowerSettingWithBackup -Name "AdvCpuPower" -Settings @(@{ SubGroup = "SUB_PROCESSOR"; Setting = "CPMINCORES"; AC = 100 })

    #>
    param(
        [Parameter(Mandatory)]
        [string]$Name,

        [hashtable[]]$Settings = @(),

        [switch]$Undo,

        [string]$BackupKey = "HKLM:\SOFTWARE\WinTweaks\Backup"
    )
    $guidPattern = '[0-9a-fA-F]{8}(?:-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}'

    if ($Undo) {
        $backupValue = (Get-ItemProperty -Path $BackupKey -Name $Name -ErrorAction SilentlyContinue).$Name
        if (-not $backupValue) {
            Write-Host "Nothing recorded for $Name, nothing to restore."
            Write-WinUtilLog -Component "PowerPlan" -Message "No backup found for $Name; nothing to restore."
            return
        }

        $backup = $backupValue | ConvertFrom-Json
        foreach ($entry in @($backup.Settings)) {
            powercfg.exe /setacvalueindex $backup.Scheme $entry.SubGroup $entry.Setting $entry.AC | Out-Null
            powercfg.exe /setdcvalueindex $backup.Scheme $entry.SubGroup $entry.Setting $entry.DC | Out-Null
            Write-Host "Restored $($entry.SubGroup) $($entry.Setting) to AC $($entry.AC), DC $($entry.DC)"
        }

        $activeScheme = [regex]::Match((@(powercfg.exe /getactivescheme) -join " "), $guidPattern).Value
        if ($activeScheme -eq $backup.Scheme) {
            powercfg.exe /setactive $backup.Scheme | Out-Null
        }

        Remove-ItemProperty -Path $BackupKey -Name $Name -ErrorAction SilentlyContinue
        Write-WinUtilLog -Component "PowerPlan" -Message "Restored $(@($backup.Settings).Count) power setting(s) recorded for $Name."
        return
    }

    $scheme = [regex]::Match((@(powercfg.exe /getactivescheme) -join " "), $guidPattern).Value
    if (-not $scheme) {
        throw "The active power plan could not be read."
    }

    $existingValue = (Get-ItemProperty -Path $BackupKey -Name $Name -ErrorAction SilentlyContinue).$Name
    $existing = if ($existingValue) { $existingValue | ConvertFrom-Json } else { $null }

    $recorded = [System.Collections.Generic.List[object]]::new()
    $toApply = [System.Collections.Generic.List[hashtable]]::new()
    foreach ($setting in $Settings) {
        $indexes = @([regex]::Matches((@(powercfg.exe /qh $scheme $setting.SubGroup $setting.Setting) -join "`n"), '0x[0-9a-fA-F]{8}') | ForEach-Object { [Convert]::ToInt32($_.Value, 16) })
        if ($indexes.Count -lt 2) {
            Write-Warning "Power setting $($setting.SubGroup) $($setting.Setting) is not available on this PC, skipping it."
            Write-WinUtilLog -Level "WARN" -Component "PowerPlan" -Message "Power setting $($setting.SubGroup) $($setting.Setting) not found; skipped."
            continue
        }
        $recorded.Add([pscustomobject]@{ SubGroup = $setting.SubGroup; Setting = $setting.Setting; AC = $indexes[-2]; DC = $indexes[-1] })
        $toApply.Add($setting)
    }

    # Applied twice on the same plan, the first backup still holds the values from before WinTweaks
    if (-not $existing -or $existing.Scheme -ne $scheme) {
        if (!(Test-Path $BackupKey)) {
            New-Item -Path $BackupKey -Force | Out-Null
        }
        $backup = [pscustomobject]@{ Scheme = $scheme; Settings = @($recorded) }
        Set-ItemProperty -Path $BackupKey -Name $Name -Type String -Value (ConvertTo-Json -InputObject $backup -Depth 4 -Compress)
    }

    foreach ($setting in $toApply) {
        powercfg.exe /setacvalueindex $scheme $setting.SubGroup $setting.Setting $setting.AC | Out-Null
        if ($setting.ContainsKey("DC")) {
            powercfg.exe /setdcvalueindex $scheme $setting.SubGroup $setting.Setting $setting.DC | Out-Null
        }
        Write-Host "Set $($setting.SubGroup) $($setting.Setting) on the active power plan"
    }
    powercfg.exe /setactive $scheme | Out-Null
    Write-WinUtilLog -Component "PowerPlan" -Message "Changed $($toApply.Count) power setting(s) for $Name on plan $scheme."
}
