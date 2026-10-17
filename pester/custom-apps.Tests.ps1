#===========================================================================
# Tests - Custom winget apps
#===========================================================================

BeforeAll {
    $script:repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
    . (Join-Path $script:repoRoot "functions\private\New-WinUtilCustomAppEntry.ps1")
    . (Join-Path $script:repoRoot "functions\private\Import-WinUtilCustomAppList.ps1")
    . (Join-Path $script:repoRoot "functions\private\Save-WinUtilCustomAppList.ps1")
    . (Join-Path $script:repoRoot "functions\private\Add-WinUtilCustomApp.ps1")
    . (Join-Path $script:repoRoot "functions\private\Remove-WinUtilCustomApp.ps1")
    . (Join-Path $script:repoRoot "functions\private\Update-WinUtilInstallAppList.ps1")

    function Write-WinUtilLog {
        param($Message, $Level, $Component)
    }
    function Show-WinUtilMessage {
        param($Message, $Title, $Button, $Icon)
    }
    function Invoke-WPFSelectedCheckboxesUpdate {
        param($type, $checkboxName)
    }
    function Initialize-InstallCategoryAppList {
        param($TargetElement, $Apps)
    }
}

Describe "New-WinUtilCustomAppEntry" {
    It "keeps only characters a WPF control name accepts in the key" {
        $customApp = New-WinUtilCustomAppEntry -WingetId "Notepad++.Notepad++"

        $customApp.Key | Should -Be "WPFInstallcustom_Notepad___Notepad__"
        $customApp.Key | Should -Match '^[A-Za-z0-9_]+$'
    }

    It "shapes the entry like a catalog app installed through winget" {
        $entry = (New-WinUtilCustomAppEntry -WingetId "Mozilla.Firefox").Entry

        $entry.category | Should -Be "Custom"
        $entry.winget | Should -Be "Mozilla.Firefox"
        $entry.choco | Should -Be "na"
        $entry.content | Should -Be "Mozilla.Firefox"
        $entry.custom | Should -BeTrue
        $entry.link | Should -Not -BeNullOrEmpty
    }
}

Describe "Custom app list" {
    BeforeEach {
        $script:sync = @{
            winutildir = $TestDrive
            selectedApps = [System.Collections.Generic.List[string]]::new()
            configs = @{
                applicationsHashtable = @{
                    WPFInstallfirefox = [pscustomobject]@{ content = "Firefox"; winget = "Mozilla.Firefox"; category = "Browsers" }
                }
            }
        }
        Remove-Item -LiteralPath (Join-Path $TestDrive "custom-apps.json") -ErrorAction SilentlyContinue

        Mock Show-WinUtilMessage { "OK" }
        Mock Update-WinUtilInstallAppList { }
        Mock Invoke-WPFSelectedCheckboxesUpdate { }
    }

    AfterEach {
        Remove-Variable -Name sync -Scope Script -ErrorAction SilentlyContinue
    }

    It "adds a valid ID, saves it and redraws the list" {
        Add-WinUtilCustomApp -WingetId "  Valve.Steam " | Should -BeTrue

        $script:sync.configs.applicationsHashtable.ContainsKey("WPFInstallcustom_Valve_Steam") | Should -BeTrue
        $saved = Get-Content -LiteralPath (Join-Path $TestDrive "custom-apps.json") -Raw | ConvertFrom-Json
        @($saved).Count | Should -Be 1
        @($saved)[0] | Should -Be "Valve.Steam"
        Should -Invoke Update-WinUtilInstallAppList -Times 1 -Exactly
    }

    It "rejects text that cannot be a winget ID" -TestCases @(
        @{ WingetId = "" }
        @{ WingetId = "two words" }
        @{ WingetId = "Bad;Id" }
        @{ WingetId = ".Leading.Dot" }
    ) {
        param($WingetId)

        Add-WinUtilCustomApp -WingetId $WingetId | Should -BeFalse
        Should -Invoke Show-WinUtilMessage -Times 1 -Exactly -ParameterFilter { $Icon -eq "Warning" }
        Test-Path -LiteralPath (Join-Path $TestDrive "custom-apps.json") | Should -BeFalse
    }

    It "does not add a package the catalog already has" {
        Add-WinUtilCustomApp -WingetId "mozilla.firefox" | Should -BeFalse

        $script:sync.configs.applicationsHashtable.Count | Should -Be 1
        Should -Invoke Show-WinUtilMessage -Times 1 -Exactly -ParameterFilter { $Message -like "*already in the list*" }
    }

    It "waits for the app list to finish drawing before changing it" {
        $script:sync.InitializedTabs = @{ Install = $true }
        $script:sync.InstallAppEntriesRendered = $false

        Add-WinUtilCustomApp -WingetId "Valve.Steam" | Should -BeFalse
        $script:sync.configs.applicationsHashtable.ContainsKey("WPFInstallcustom_Valve_Steam") | Should -BeFalse
    }

    It "removes a custom app and its selection" {
        Add-WinUtilCustomApp -WingetId "Valve.Steam" | Out-Null
        $script:sync.selectedApps.Add("WPFInstallcustom_Valve_Steam")

        Remove-WinUtilCustomApp -AppKey "WPFInstallcustom_Valve_Steam"

        $script:sync.configs.applicationsHashtable.ContainsKey("WPFInstallcustom_Valve_Steam") | Should -BeFalse
        Should -Invoke Invoke-WPFSelectedCheckboxesUpdate -Times 1 -Exactly -ParameterFilter { $type -eq "Remove" }
        # Windows PowerShell writes an empty array with a blank line inside it
        (Get-Content -LiteralPath (Join-Path $TestDrive "custom-apps.json") -Raw) -replace '\s', '' | Should -Be "[]"
    }

    It "leaves catalog apps alone" {
        Remove-WinUtilCustomApp -AppKey "WPFInstallfirefox"

        $script:sync.configs.applicationsHashtable.ContainsKey("WPFInstallfirefox") | Should -BeTrue
        Should -Invoke Update-WinUtilInstallAppList -Times 0 -Exactly
    }

    It "restores saved custom apps at startup" {
        Set-Content -LiteralPath (Join-Path $TestDrive "custom-apps.json") -Value '["Valve.Steam", "", "Discord.Discord"]'

        Import-WinUtilCustomAppList

        $script:sync.configs.applicationsHashtable.ContainsKey("WPFInstallcustom_Valve_Steam") | Should -BeTrue
        $script:sync.configs.applicationsHashtable.ContainsKey("WPFInstallcustom_Discord_Discord") | Should -BeTrue
        $script:sync.configs.applicationsHashtable.Count | Should -Be 3
    }

    It "ignores an unreadable saved list" {
        Set-Content -LiteralPath (Join-Path $TestDrive "custom-apps.json") -Value '{not json'
        Mock Write-WinUtilLog { }

        { Import-WinUtilCustomAppList } | Should -Not -Throw
        $script:sync.configs.applicationsHashtable.Count | Should -Be 1
        Should -Invoke Write-WinUtilLog -Times 1 -Exactly -ParameterFilter { $Level -eq "WARN" }
    }
}
