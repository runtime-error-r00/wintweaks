function Set-WinUtilRegistryWithBackup {
    <#

    .SYNOPSIS
        Writes registry values whose original state differs from PC to PC, keeping that state for undo

    .DESCRIPTION
        Driver and device keys (display adapters, USB controllers) already carry values the
        driver installed, so a fixed OriginalValue in tweaks.json would be wrong on most PCs.
        Before the first write each value's previous state is recorded under
        HKLM:\SOFTWARE\WinTweaks\Backup\<Name>, and -Undo puts exactly that state back.

        Applying again keeps the state recorded the first time, so the backup always holds the
        values from before WinTweaks touched them.

    .PARAMETER Name
        The backup name, one per tweak.

    .PARAMETER Path
        The registry keys to write to. Missing keys are created.

    .PARAMETER Settings
        Hashtables with Name, Type and Value, written to every key in Path.

    .PARAMETER Undo
        Restore the recorded state and delete the backup.

    .PARAMETER BackupKey
        Where the previous state is recorded. Only tests point it elsewhere.

    .EXAMPLE
        Set-WinUtilRegistryWithBackup -Name "AdvUsbPower" -Path "HKLM:\SYSTEM\CurrentControlSet\Services\USB" -Settings @(@{ Name = "DisableSelectiveSuspend"; Type = "DWord"; Value = 1 })

    #>
    param(
        [Parameter(Mandatory)]
        [string]$Name,

        [string[]]$Path = @(),

        [hashtable[]]$Settings = @(),

        [switch]$Undo,

        [string]$BackupKey = "HKLM:\SOFTWARE\WinTweaks\Backup"
    )

    $recorded = [System.Collections.Generic.List[object]]::new()
    $backupValue = (Get-ItemProperty -Path $BackupKey -Name $Name -ErrorAction SilentlyContinue).$Name
    if ($backupValue) {
        # Windows PowerShell passes a JSON array down the pipeline as one object; the assignment unrolls it
        $parsed = $backupValue | ConvertFrom-Json
        foreach ($entry in $parsed) {
            $recorded.Add($entry)
        }
    }

    if ($Undo) {
        if ($recorded.Count -eq 0) {
            Write-Host "Nothing recorded for $Name, nothing to restore."
            Write-WinUtilLog -Component "Registry" -Message "No backup found for $Name; nothing to restore."
            return
        }

        foreach ($entry in $recorded) {
            $key = Get-Item -Path $entry.Path -ErrorAction SilentlyContinue
            if ($entry.Exists) {
                $value = if ($entry.Kind -eq "Binary") { [byte[]]@($entry.Value) } elseif ($entry.Kind -eq "MultiString") { [string[]]@($entry.Value) } else { $entry.Value }
                Set-WinUtilRegistry -Name $entry.Name -Path $entry.Path -Type $entry.Kind -Value $value
            } elseif ($key -and $key.GetValueNames() -contains $entry.Name) {
                Set-WinUtilRegistry -Name $entry.Name -Path $entry.Path -Type "DWord" -Value "<RemoveEntry>"
            }
        }

        Remove-ItemProperty -Path $BackupKey -Name $Name -ErrorAction SilentlyContinue
        Write-WinUtilLog -Component "Registry" -Message "Restored $($recorded.Count) registry value(s) recorded for $Name."
        return
    }

    if (@($Path).Count -eq 0) {
        Write-Host "No registry keys to change for $Name."
        Write-WinUtilLog -Level "WARN" -Component "Registry" -Message "No registry keys to change for $Name."
        return
    }

    foreach ($keyPath in $Path) {
        foreach ($setting in $Settings) {
            $alreadyRecorded = $recorded | Where-Object { $_.Path -eq $keyPath -and $_.Name -eq $setting.Name }
            if (-not $alreadyRecorded) {
                $previous = [ordered]@{ Path = $keyPath; Name = $setting.Name; Exists = $false; Kind = $null; Value = $null }
                $key = Get-Item -Path $keyPath -ErrorAction SilentlyContinue
                if ($key -and $key.GetValueNames() -contains $setting.Name) {
                    $previous.Exists = $true
                    $previous.Kind = $key.GetValueKind($setting.Name).ToString()
                    $previous.Value = $key.GetValue($setting.Name, $null, [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)
                }
                $recorded.Add([pscustomobject]$previous)
            }
        }
    }

    # The backup is written before anything changes, so a run that stops halfway can still be undone
    if (!(Test-Path $BackupKey)) {
        New-Item -Path $BackupKey -Force | Out-Null
    }
    Set-ItemProperty -Path $BackupKey -Name $Name -Type String -Value (ConvertTo-Json -InputObject @($recorded) -Depth 4 -Compress)

    foreach ($keyPath in $Path) {
        foreach ($setting in $Settings) {
            Set-WinUtilRegistry -Name $setting.Name -Path $keyPath -Type $setting.Type -Value $setting.Value
        }
    }
}
