#===========================================================================
# Tests - Advanced page helpers
#===========================================================================

BeforeAll {
    $script:repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
    . (Join-Path $script:repoRoot "functions\private\Set-WinUtilRegistry.ps1")
    . (Join-Path $script:repoRoot "functions\private\Set-WinUtilRegistryWithBackup.ps1")
    . (Join-Path $script:repoRoot "functions\private\Get-WinUtilDisplayAdapterKey.ps1")
    . (Join-Path $script:repoRoot "functions\private\Set-WinUtilPowerSettingWithBackup.ps1")
    . (Join-Path $script:repoRoot "functions\private\Get-WinUtilTabTweaks.ps1")
    . (Join-Path $script:repoRoot "functions\private\Get-WinUtilAdvancedGroup.ps1")

    function Write-WinUtilLog {
        param($Message, $Level, $Component)
    }
}

Describe "Set-WinUtilRegistryWithBackup" {
    BeforeEach {
        Mock Write-Host { }
        $script:deviceKey = "TestRegistry:\Device"
        $script:backupKey = "TestRegistry:\Backup"
        New-Item -Path $script:deviceKey -Force | Out-Null
        Remove-Item -Path $script:backupKey -Recurse -Force -ErrorAction SilentlyContinue
        New-ItemProperty -Path $script:deviceKey -Name "Existing" -PropertyType DWord -Value 7 -Force | Out-Null
        New-ItemProperty -Path $script:deviceKey -Name "Blob" -PropertyType Binary -Value ([byte[]](1, 2)) -Force | Out-Null
        Remove-ItemProperty -Path $script:deviceKey -Name "Added" -ErrorAction SilentlyContinue
    }

    It "restores changed values and removes values that did not exist" {
        $settings = @(
            @{ Name = "Existing"; Type = "DWord"; Value = 0 },
            @{ Name = "Blob"; Type = "Binary"; Value = [byte[]](0x31, 0x00) },
            @{ Name = "Added"; Type = "DWord"; Value = 1 }
        )

        Set-WinUtilRegistryWithBackup -Name "Test" -Path $script:deviceKey -Settings $settings -BackupKey $script:backupKey
        (Get-ItemProperty -Path $script:deviceKey).Existing | Should -Be 0
        (Get-ItemProperty -Path $script:deviceKey).Added | Should -Be 1

        Set-WinUtilRegistryWithBackup -Name "Test" -Undo -BackupKey $script:backupKey
        $restored = Get-ItemProperty -Path $script:deviceKey
        $restored.Existing | Should -Be 7
        @($restored.Blob) | Should -Be @(1, 2)
        $restored.PSObject.Properties.Name | Should -Not -Contain "Added"
        (Get-ItemProperty -Path $script:backupKey).PSObject.Properties.Name | Should -Not -Contain "Test"
    }

    It "keeps the state from before the first run when applied twice" {
        $settings = @(@{ Name = "Existing"; Type = "DWord"; Value = 0 })

        Set-WinUtilRegistryWithBackup -Name "Test" -Path $script:deviceKey -Settings $settings -BackupKey $script:backupKey
        Set-WinUtilRegistryWithBackup -Name "Test" -Path $script:deviceKey -Settings $settings -BackupKey $script:backupKey
        Set-WinUtilRegistryWithBackup -Name "Test" -Undo -BackupKey $script:backupKey

        (Get-ItemProperty -Path $script:deviceKey).Existing | Should -Be 7
    }

    It "creates a missing key and changes nothing when there is no key to write to" {
        Set-WinUtilRegistryWithBackup -Name "Test" -Path "TestRegistry:\Missing" -Settings @(@{ Name = "Value"; Type = "DWord"; Value = 1 }) -BackupKey $script:backupKey
        (Get-ItemProperty -Path "TestRegistry:\Missing").Value | Should -Be 1

        Set-WinUtilRegistryWithBackup -Name "Empty" -Path @() -Settings @(@{ Name = "Value"; Type = "DWord"; Value = 1 }) -BackupKey $script:backupKey
        (Get-ItemProperty -Path $script:backupKey).PSObject.Properties.Name | Should -Not -Contain "Empty"
    }
}

Describe "Get-WinUtilDisplayAdapterKey" {
    It "returns the adapter keys of the requested vendor only" {
        Mock Get-ChildItem {
            foreach ($adapter in @(@("0000", "PCI\VEN_8086&DEV_A780"), @("0001", "pci\ven_10de&dev_2684"), @("Properties", ""))) {
                $key = [pscustomobject]@{ PSChildName = $adapter[0]; DeviceId = $adapter[1] }
                $key | Add-Member -MemberType ScriptMethod -Name GetValue -Value { param($Name) $this.DeviceId }
                $key
            }
        }

        @(Get-WinUtilDisplayAdapterKey -Vendor NVIDIA) | Should -Be @("HKLM:\SYSTEM\CurrentControlSet\Control\Class\{4d36e968-e325-11ce-bfc1-08002be10318}\0001")
        @(Get-WinUtilDisplayAdapterKey -Vendor AMD) | Should -BeNullOrEmpty
    }
}

Describe "Set-WinUtilPowerSettingWithBackup" {
    BeforeEach {
        Mock Write-Host { }
        $script:backupKey = "TestRegistry:\PowerBackup"
        Remove-Item -Path $script:backupKey -Recurse -Force -ErrorAction SilentlyContinue
        $script:powercfgCalls = [System.Collections.Generic.List[string]]::new()
        Mock powercfg.exe {
            $script:powercfgCalls.Add($args -join " ")
            switch ($args[0]) {
                "/getactivescheme" { "Power Scheme GUID: 381b4222-f694-41f0-9685-ff5bb260df2e  (Balanced)" }
                "/qh" {
                    if ($args[3] -eq "MISSING") { return }
                    "    Minimum Possible Setting: 0x00000000"
                    "    Maximum Possible Setting: 0x00000064"
                    "    Current AC Power Setting Index: 0x0000000a"
                    "    Current DC Power Setting Index: 0x00000005"
                }
            }
        }
    }

    It "records the previous AC and DC values and writes them back on undo" {
        Set-WinUtilPowerSettingWithBackup -Name "Cpu" -BackupKey $script:backupKey -Settings @(
            @{ SubGroup = "SUB_PROCESSOR"; Setting = "CPMINCORES"; AC = 100 },
            @{ SubGroup = "SUB_PROCESSOR"; Setting = "MISSING"; AC = 1 }
        )

        $script:powercfgCalls | Should -Contain "/setacvalueindex 381b4222-f694-41f0-9685-ff5bb260df2e SUB_PROCESSOR CPMINCORES 100"
        $script:powercfgCalls | Should -Not -Contain "/setacvalueindex 381b4222-f694-41f0-9685-ff5bb260df2e SUB_PROCESSOR MISSING 1"

        $script:powercfgCalls.Clear()
        Set-WinUtilPowerSettingWithBackup -Name "Cpu" -Undo -BackupKey $script:backupKey

        $script:powercfgCalls | Should -Contain "/setacvalueindex 381b4222-f694-41f0-9685-ff5bb260df2e SUB_PROCESSOR CPMINCORES 10"
        $script:powercfgCalls | Should -Contain "/setdcvalueindex 381b4222-f694-41f0-9685-ff5bb260df2e SUB_PROCESSOR CPMINCORES 5"
        (Get-ItemProperty -Path $script:backupKey).PSObject.Properties.Name | Should -Not -Contain "Cpu"
    }
}

Describe "Get-WinUtilAdvancedGroup" {
    BeforeAll {
        $script:sync = @{ configs = @{ tweaks = (Get-Content -Path (Join-Path $script:repoRoot "config\tweaks.json") -Raw | ConvertFrom-Json) } }
    }

    It "applies every group tweak except drop-downs and standalone actions" {
        $general = Get-WinUtilAdvancedGroup -Group "General"
        $keyboard = Get-WinUtilAdvancedGroup -Group "KeyboardMouse"

        $general.Tweaks | Should -Contain "WPFTweaksAdvSystemTimers"
        $general.Tweaks | Should -Not -Contain "WPFTweaksAdvCoreIsolation"
        $keyboard.Tweaks | Should -Contain "WPFTweaksAdvMouseAcceleration"
        $keyboard.Tweaks | Should -Not -Contain "WPFTweaksAdvDataQueueSize"
        $general.Tweaks | Should -Not -Contain "WPFTweaksTelemetry"
    }

    It "gives every group at least one tweak" {
        foreach ($group in "General", "KeyboardMouse", "GPU", "CPU") {
            (Get-WinUtilAdvancedGroup -Group $group).Tweaks | Should -Not -BeNullOrEmpty
        }
    }
}

Describe "Advanced tweaks config" {
    It "keeps every Advanced entry in a known category and panel" {
        $tweaks = Get-Content -Path (Join-Path $script:repoRoot "config\tweaks.json") -Raw | ConvertFrom-Json
        $advanced = @($tweaks.PSObject.Properties | Where-Object { $_.Value.tab -eq "Advanced" })
        $categories = @("a__General System", "b__Keyboard and Mouse", "c__GPU", "d__CPU")

        $advanced | Should -Not -BeNullOrEmpty
        foreach ($entry in $advanced) {
            $entry.Name | Should -Match '^WPFTweaksAdv'
            $categories | Should -Contain $entry.Value.category
            @("1", "2") | Should -Contain $entry.Value.panel
        }
    }

    It "undoes every script-based Advanced tweak" {
        $tweaks = Get-Content -Path (Join-Path $script:repoRoot "config\tweaks.json") -Raw | ConvertFrom-Json
        $withoutUndo = @(
            $tweaks.PSObject.Properties |
                Where-Object { $_.Value.tab -eq "Advanced" -and $_.Value.InvokeScript -and -not $_.Value.UndoScript } |
                ForEach-Object Name
        )

        $withoutUndo | Should -BeNullOrEmpty
    }
}
