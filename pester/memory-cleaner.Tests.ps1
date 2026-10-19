#===========================================================================
# Tests - Memory Cleaner logic that does not call into Windows
#===========================================================================

BeforeAll {
    $script:repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
    foreach ($file in @(
        "Get-WinUtilMemoryAreas.ps1",
        "Get-WinUtilMemoryCleanReport.ps1",
        "Get-WinUtilMemoryCleanerSettings.ps1",
        "Save-WinUtilMemoryCleanerSettings.ps1"
    )) {
        . (Join-Path $script:repoRoot "functions\private\$file")
    }

    function Write-WinUtilLog {
        param($Message, $Level, $Component)
    }

    function New-TestSnapshot {
        param($Used = 0, $Standby = 0, $Modified = 0, $Free = 0)
        [pscustomobject]@{
            TotalBytes = 16GB; AvailableBytes = 16GB - $Used; UsedBytes = $Used; LoadPercent = 0
            FreeBytes = $Free; StandbyBytes = $Standby; ModifiedBytes = $Modified
        }
    }
}

Describe "Get-WinUtilMemoryAreas" {
    It "cleans working sets first and the combined page list last of the defaults" {
        $keys = @(Get-WinUtilMemoryAreas -Build 26100 | ForEach-Object Key)
        $keys | Should -Be @("ProcessWorkingSets", "SystemFileCache", "ModifiedPageList", "StandbyListLowPriority", "StandbyList", "CombinedPageList", "RegistryCache")
    }

    It "marks areas newer than the build as unsupported" {
        $areas = Get-WinUtilMemoryAreas -Build 7601
        ($areas | Where-Object Key -eq "CombinedPageList").Supported | Should -BeFalse
        ($areas | Where-Object Key -eq "RegistryCache").Supported | Should -BeFalse
        ($areas | Where-Object Key -eq "StandbyList").Supported | Should -BeTrue
    }
}

Describe "ConvertTo-WinUtilMemoryCleanerSettings" {
    It "ticks every area except the registry cache by default" {
        $settings = ConvertTo-WinUtilMemoryCleanerSettings -Settings $null
        $settings.Areas | Should -Contain "StandbyList"
        $settings.Areas | Should -Not -Contain "RegistryCache"
    }

    It "drops unknown areas and keeps an empty selection empty" {
        @((ConvertTo-WinUtilMemoryCleanerSettings -Settings @{ Areas = @("StandbyList", "Bogus") }).Areas) | Should -Be @("StandbyList")
        @((ConvertTo-WinUtilMemoryCleanerSettings -Settings @{ Areas = @() }).Areas).Count | Should -Be 0
    }
}

Describe "Memory Cleaner settings file" {
    It "round-trips through disk" {
        $path = Join-Path $TestDrive "memorycleaner.json"
        $null = Save-WinUtilMemoryCleanerSettings -Path $path -Settings @{ Areas = @("StandbyList", "ModifiedPageList") }

        @((Get-WinUtilMemoryCleanerSettings -Path $path).Areas) | Should -Be @("ModifiedPageList", "StandbyList")
    }

    It "falls back to defaults when the file is damaged or missing" {
        $path = Join-Path $TestDrive "broken.json"
        Set-Content -Path $path -Value "{ not json"
        (Get-WinUtilMemoryCleanerSettings -Path $path).Areas | Should -Contain "ProcessWorkingSets"
        (Get-WinUtilMemoryCleanerSettings -Path (Join-Path $TestDrive "missing.json")).Areas | Should -Contain "ProcessWorkingSets"
    }
}

Describe "Get-WinUtilMemoryCleanReport" {
    It "measures each area on the figure it acts on" {
        $start = New-TestSnapshot -Used 8GB -Standby 4GB -Modified 512MB -Free 1GB
        $afterTrim = New-TestSnapshot -Used 6GB -Standby 6GB -Modified 512MB
        $afterFlush = New-TestSnapshot -Used 6GB -Standby 6GB -Modified 0
        $afterPurge = New-TestSnapshot -Used 6GB -Standby 1GB -Modified 0 -Free 6GB

        $report = Get-WinUtilMemoryCleanReport -Before $start -After $afterPurge -Results @(
            [pscustomobject]@{ Key = "ProcessWorkingSets"; Label = "WS"; Measure = "Used"; Status = "Cleaned"; Before = $start; After = $afterTrim },
            [pscustomobject]@{ Key = "ModifiedPageList"; Label = "Mod"; Measure = "Modified"; Status = "Cleaned"; Before = $afterTrim; After = $afterFlush },
            [pscustomobject]@{ Key = "StandbyList"; Label = "SB"; Measure = "Standby"; Status = "Cleaned"; Before = $afterFlush; After = $afterPurge },
            [pscustomobject]@{ Key = "CombinedPageList"; Label = "CPL"; Measure = "Combined"; Status = "Cleaned"; Before = $afterPurge; After = $afterPurge; CombinedBytes = 64MB }
        )

        @($report.Areas | ForEach-Object FreedBytes) | Should -Be @(2GB, 512MB, 5GB, 64MB)
        # Trimmed pages are purged again from standby, so the total is the free list growth, not the sum
        $report.TotalFreedBytes | Should -Be 5GB
        $report.FailedCount | Should -Be 0
    }

    It "counts growth as nothing released and leaves failed areas unmeasured" {
        $low = New-TestSnapshot -Standby 1GB
        $high = New-TestSnapshot -Standby 2GB
        $report = Get-WinUtilMemoryCleanReport -Before $low -After $high -Results @(
            [pscustomobject]@{ Key = "StandbyList"; Label = "SB"; Measure = "Standby"; Status = "Cleaned"; Before = $low; After = $high },
            [pscustomobject]@{ Key = "RegistryCache"; Label = "Reg"; Measure = "Used"; Status = "Failed"; Message = "Access is denied."; Before = $high; After = $high }
        )

        $report.Areas[0].FreedBytes | Should -Be 0
        $report.Areas[1].FreedBytes | Should -BeNullOrEmpty
        $report.FailedCount | Should -Be 1
        (Format-WinUtilMemoryCleanReport -Report $report) | Should -Contain "Reg: failed - Access is denied."
    }

    It "adds up the areas when the free list could not be read" {
        $before = New-TestSnapshot -Used 8GB
        $after = New-TestSnapshot -Used 6GB
        $before.FreeBytes = $null
        $after.FreeBytes = $null
        $report = Get-WinUtilMemoryCleanReport -Before $before -After $after -Results @(
            [pscustomobject]@{ Key = "ProcessWorkingSets"; Label = "WS"; Measure = "Used"; Status = "Cleaned"; Before = $before; After = $after },
            [pscustomobject]@{ Key = "CombinedPageList"; Label = "CPL"; Measure = "Combined"; Status = "Cleaned"; Before = $after; After = $after; CombinedBytes = 64MB }
        )
        $report.TotalFreedBytes | Should -Be (2GB + 64MB)
    }

    It "reports an area that frees no memory itself as done" {
        $snapshot = New-TestSnapshot -Used 4GB
        $report = Get-WinUtilMemoryCleanReport -Before $snapshot -After $snapshot -Results @(
            [pscustomobject]@{ Key = "RegistryCache"; Label = "Reg"; Measure = "None"; Status = "Cleaned"; Before = $snapshot; After = (New-TestSnapshot -Used 2GB) }
        )
        $report.Areas[0].FreedBytes | Should -BeNullOrEmpty
        $report.TotalFreedBytes | Should -Be 0
        (Format-WinUtilMemoryCleanReport -Report $report) | Should -Contain "Reg: done"
    }

    It "reports n/a when the page lists could not be read" {
        $unknown = New-TestSnapshot
        $unknown.StandbyBytes = $null
        Measure-WinUtilMemoryAreaFreed -Measure "Standby" -Before $unknown -After $unknown | Should -BeNullOrEmpty
        Format-WinUtilMemorySize $null | Should -Be "n/a"
        Format-WinUtilMemorySize 1536MB | Should -Be ("{0:N0} MB" -f 1536)
    }
}
