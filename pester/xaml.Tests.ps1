#===========================================================================
# Tests - XAML Control Wiring

BeforeAll {
    $script:repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
    $script:configRoot = Join-Path $script:repoRoot "config"
    $script:functionRoot = Join-Path $script:repoRoot "functions"
    $script:scriptsRoot = Join-Path $script:repoRoot "scripts"
    $script:xamlPath = Join-Path $script:repoRoot "xaml\inputXML.xaml"
    $script:uiScriptPath = Join-Path $script:functionRoot "private\Start-WinUtilUserInterface.ps1"
    $script:buttonScriptPath = Join-Path $script:functionRoot "public\Invoke-WPFButton.ps1"
    $script:xamlText = Get-Content -Path $script:xamlPath -Raw
    $script:xaml = [xml]$script:xamlText
    $script:xamlNamespace = New-Object System.Xml.XmlNamespaceManager -ArgumentList $script:xaml.NameTable
    $script:xamlNamespace.AddNamespace("x", "http://schemas.microsoft.com/winfx/2006/xaml")

    function script:Get-WinUtilConfigObject {
        param([string]$Name)

        Get-Content -Path (Join-Path $script:configRoot "$Name.json") -Raw | ConvertFrom-Json
    }

    function script:Get-WinUtilSourceText {
        Get-ChildItem -Path @($script:functionRoot, $script:scriptsRoot) -Filter *.ps1 -Recurse |
            ForEach-Object { Get-Content -Path $_.FullName -Raw } |
            Out-String
    }

    function script:Get-WinUtilTopLevelFunctionNames {
        Get-ChildItem -Path $script:functionRoot -Filter *.ps1 -Recurse | ForEach-Object {
            $tokens = $null
            $syntaxErrors = $null
            $ast = [System.Management.Automation.Language.Parser]::ParseFile($_.FullName, [ref]$tokens, [ref]$syntaxErrors)
            if ($syntaxErrors.Count -ne 0) {
                throw ($syntaxErrors | Out-String)
            }

            $ast.EndBlock.Statements |
                Where-Object { $_ -is [System.Management.Automation.Language.FunctionDefinitionAst] } |
                ForEach-Object { $_.Name }
        } | Sort-Object -Unique
    }

    function script:Get-WinUtilXamlNamedControls {
        $nodes = $script:xaml.SelectNodes("//*[@Name or @x:Name]", $script:xamlNamespace)
        foreach ($node in $nodes) {
            $controlName = $node.GetAttribute("Name")
            if ([string]::IsNullOrWhiteSpace($controlName)) {
                $controlName = $node.GetAttribute("Name", "http://schemas.microsoft.com/winfx/2006/xaml")
            }

            [pscustomobject]@{
                Name = $controlName
                Type = $node.LocalName
            }
        }
    }

    function script:Get-WinUtilXamlRuntimeNamedControls {
        $nodes = $script:xaml.SelectNodes("//*[@Name]")
        foreach ($node in $nodes) {
            [pscustomobject]@{
                Name = $node.GetAttribute("Name")
                Type = $node.LocalName
            }
        }
    }

    function script:Get-WinUtilGeneratedControlNames {
        $names = New-Object System.Collections.Generic.List[string]
        foreach ($configName in @("appnavigation", "tweaks", "appx")) {
            $config = Get-WinUtilConfigObject -Name $configName
            foreach ($entry in $config.PSObject.Properties.Name) {
                $names.Add($entry)
            }
        }

        $applications = Get-WinUtilConfigObject -Name "applications"
        foreach ($entry in $applications.PSObject.Properties.Name) {
            $names.Add($entry)
            $names.Add(($entry -replace "-", "_"))
        }

        $names | Sort-Object -Unique
    }

    function script:Get-WinUtilButtonSwitchNames {
        $buttonSource = Get-Content -Path $script:buttonScriptPath -Raw
        [regex]::Matches($buttonSource, '"(WPF[A-Za-z0-9_]+)"\s*\{') |
            ForEach-Object { $_.Groups[1].Value } |
            Sort-Object -Unique
    }

    function script:Test-WinUtilNameInSet {
        param(
            [Parameter(Mandatory)]
            [string]$Name,

            [Parameter(Mandatory)]
            [string[]]$Set
        )

        foreach ($item in $Set) {
            if ($item -ieq $Name) {
                return $true
            }
        }

        return $false
    }
}

Describe "Interface startup failures" {
    BeforeAll {
        function Measure-WinUtilStep { param($Scope, $Name, $ScriptBlock) $null = $Scope, $Name; & $ScriptBlock }
        function Write-WinUtilLog { param($Level, $Component, $Message) $null = $Level, $Component, $Message }
    }

    BeforeEach {
        . $script:uiScriptPath
        $script:sync = [Hashtable]::Synchronized(@{
            StepTimings = [System.Collections.ArrayList]::Synchronized([System.Collections.ArrayList]::new())
            preferences = @{ theme = "Auto" }
        })
        $script:inputXML = '<NotAWindow xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" />'

        Mock Measure-WinUtilStep { & $ScriptBlock }
        Mock Write-WinUtilLog { }
        Mock Write-Host { }
    }

    It "throws when the XAML cannot create the window" {
        { Start-WinUtilUserInterface } | Should -Throw "Failed to parse the XAML content*"

        Should -Invoke Write-WinUtilLog -Times 1 -Exactly -ParameterFilter {
            $Level -eq "ERROR" -and $Component -eq "UI"
        }
    }

    It "exits a direct file process but returns to an in-memory caller after an interface failure" {
        $mainScript = Get-Content -Path (Join-Path $script:scriptsRoot "main.ps1") -Raw

        $mainScript | Should -Match '\$uiFailed = \$true[\s\S]*if \(\$uiFailed\) \{\s*\$global:LASTEXITCODE = 1\s*if \(\$script:WinUtilIsFileProcess\) \{ exit 1 \}\s*return 1'
    }
}

Describe "XAML document" {
    It "loads inputXML.xaml as a WPF window XML document" {
        $script:xaml.DocumentElement.LocalName | Should -Be "Window"
    }

    It "contains expected core controls" {
        $xamlNames = @(Get-WinUtilXamlRuntimeNamedControls | ForEach-Object { $_.Name })
        $requiredControls = @(
            "WPFMainGrid",
            "NavDockPanel",
            "GridBesideNavDockPanel",
            "WPFTabNav",
            "WPFTab1",
            "WPFTab2",
            "WPFTab4",
            "WPFTab6",
            "WPFTab1BT",
            "WPFTab2BT",
            "WPFTab4BT",
            "SearchBar",
            "SearchBarIcon",
            "SearchBarClearButton",
            "appscategory",
            "appspanel",
            "tweakspanel",
            "appxpanel",
            "WPFstandard",
            "WPFminimal",
            "WPFAdvanced",
            "WPFClearTweaksSelection",
            "WPFGetInstalledTweaks",
            "WPFAppxRemoval",
            "WPFTweaksbutton",
            "WPFUndoall",
            "WPFUpdatesdefault",
            "WPFUpdatessecurity",
            "WPFDefaultAppxSelection",
            "WPFGetInstalledAppx",
            "WPFSelectAllAppx",
            "WPFClearAppxSelection",
            "WPFBackToTweaks",
            "WPFInstallSelectedAppx",
            "WPFRemoveSelectedAppx"
        )

        $missingControls = @($requiredControls | Where-Object { -not (Test-WinUtilNameInSet -Name $_ -Set $xamlNames) })
        if ($missingControls.Count -gt 0) {
            throw ($missingControls -join "`n")
        }
    }



    It "presents the two Updates profiles with accurate action labels" {
        $updatesTab = $script:xaml.SelectSingleNode('//*[local-name()="TabItem"][@Name="WPFTab4"]')
        $profileGrid = $updatesTab.SelectSingleNode('.//*[local-name()="UniformGrid"]')
        $expectedButtons = @{
            WPFUpdatessecurity = "Apply Recommended"
            WPFUpdatesdefault = "Restore Defaults"
        }

        $profileGrid.GetAttribute("Columns") | Should -Be "2"
        $updatesTab.SelectSingleNode('.//*[@Name="WPFUpdatesdisable"]') | Should -BeNullOrEmpty
        foreach ($buttonName in $expectedButtons.Keys) {
            $button = $updatesTab.SelectSingleNode(".//*[local-name()='Button'][@Name='$buttonName']")
            $button.GetAttribute("Content") | Should -Be $expectedButtons[$buttonName]
        }
        $updatesTab.SelectSingleNode('.//*[@Name="updatespanel"]') | Should -BeNullOrEmpty
    }

    It "defines core tabs in the expected order" {
        $tabItems = @($script:xaml.SelectNodes('//*[local-name()="TabControl"][@Name="WPFTabNav"]/*[local-name()="TabItem"]'))
        $actualTabs = @($tabItems | ForEach-Object { "$($_.GetAttribute("Name")):$($_.GetAttribute("Header"))" })
        $expectedTabs = @(
            "WPFTab1:Install",
            "WPFTab2:Tweaks",
            "WPFTab4:Updates",
            "WPFTab6:AppX"
        )

        if (@($actualTabs).Count -ne $expectedTabs.Count) {
            throw "Expected $($expectedTabs.Count) tabs but found $(@($actualTabs).Count): $($actualTabs -join ', ')"
        }

        for ($index = 0; $index -lt $expectedTabs.Count; $index++) {
            if ($actualTabs[$index] -ne $expectedTabs[$index]) {
                throw "Tab order mismatch at index ${index}: expected $($expectedTabs[$index]), found $($actualTabs[$index])"
            }
        }
    }



    It "stacks the sidebar navigation from the top and centers top bar controls vertically" {
        $navPanel = $script:xaml.SelectSingleNode('//*[local-name()="StackPanel"][@Name="NavDockPanel"]')
        $navPanel.GetAttribute("Orientation") | Should -Be "Vertical"
        $navPanel.GetAttribute("VerticalAlignment") | Should -Be "Top"
        $navPanel.ParentNode.GetAttribute("Name") | Should -Be "WPFSidebar"

        $minimizeButton = $script:xaml.SelectSingleNode('//*[local-name()="Button"][@Name="WPFMinimizeButton"]')
        $actionPanel = $minimizeButton.ParentNode
        $topBarButtonNames = @(
            "ThemeButton",
            "FontScalingButton",
            "SettingsButton",
            "WPFMinimizeButton",
            "WPFMaximizeButton",
            "WPFCloseButton"
        )

        $actionPanel.GetAttribute("VerticalAlignment") | Should -Be "Center"

        foreach ($buttonName in $topBarButtonNames) {
            $button = $script:xaml.SelectSingleNode("//*[local-name()='Button'][@Name='$buttonName']")
            $button.GetAttribute("VerticalAlignment") | Should -Be "Center"
        }
    }





    It "scopes toggle button styles without leaking into combo boxes" {
        $resources = $script:xaml.SelectSingleNode('//*[local-name()="Window.Resources"]')
        $implicitToggleStyles = @($resources.SelectNodes('./*[local-name()="Style"][@TargetType="ToggleButton" or @TargetType="{x:Type ToggleButton}"][not(@x:Key)]', $script:xamlNamespace))
        $tabStyle = $resources.SelectSingleNode('./*[local-name()="Style"][@x:Key="TabToggleButton"]', $script:xamlNamespace)
        $comboToggleStyle = $resources.SelectSingleNode('./*[local-name()="Style"][@x:Key="ComboBoxToggleButtonStyle"]', $script:xamlNamespace)
        $comboStyle = $resources.SelectSingleNode('./*[local-name()="Style"][@TargetType="ComboBox"]')
        $comboToggle = $comboStyle.SelectSingleNode('.//*[local-name()="ToggleButton"][@Name="ToggleButton"]')
        $comboItemStyle = $resources.SelectSingleNode('./*[local-name()="Style"][@TargetType="ComboBoxItem"]')
        $navButtons = @($script:xaml.SelectNodes('//*[local-name()="StackPanel"][@Name="NavDockPanel"]/*[local-name()="ToggleButton"]'))

        $implicitToggleStyles | Should -BeNullOrEmpty
        $tabStyle | Should -Not -BeNullOrEmpty
        $comboToggleStyle | Should -Not -BeNullOrEmpty
        $comboToggle.GetAttribute("Style") | Should -Be "{StaticResource ComboBoxToggleButtonStyle}"
        $comboItemStyle | Should -Not -BeNullOrEmpty
        $navButtons.Count | Should -Be 3
        @($navButtons | ForEach-Object { $_.GetAttribute("Name") }) | Should -Be @("WPFTab2BT", "WPFTab1BT", "WPFTab4BT")
        foreach ($navButton in $navButtons) {
            $navButton.GetAttribute("Style") | Should -Be "{StaticResource TabToggleButton}"
        }
    }

    It "uses state-aware maximize and restore icons" {
        $themes = Get-WinUtilConfigObject -Name "themes"
        $minimizeButton = $script:xaml.SelectSingleNode('//*[local-name()="Button"][@Name="WPFMinimizeButton"]')
        $maximizeButton = $script:xaml.SelectSingleNode('//*[local-name()="Button"][@Name="WPFMaximizeButton"]')
        $closeButton = $script:xaml.SelectSingleNode('//*[local-name()="Button"][@Name="WPFCloseButton"]')
        $maximizeStyle = $maximizeButton.SelectSingleNode('./*[local-name()="Button.Style"]/*[local-name()="Style"]')
        $maximizeIcon = $maximizeStyle.SelectSingleNode('./*[local-name()="Setter"][@Property="Content"]')
        $maximizedTrigger = $maximizeStyle.SelectSingleNode('./*[local-name()="Style.Triggers"]/*[local-name()="DataTrigger"][@Value="Maximized"]')
        $restoreIcon = $maximizedTrigger.SelectSingleNode('./*[local-name()="Setter"][@Property="Content"]')

        foreach ($button in @($minimizeButton, $maximizeButton, $closeButton)) {
            $button.GetAttribute("FontFamily") | Should -Be "Segoe MDL2 Assets"
            $button.GetAttribute("FontSize") | Should -Be "{DynamicResource CloseIconFontSize}"
            $button.GetAttribute("Margin") | Should -BeIn @("0", "0,0,0,0")
        }

        $minimizeButton.GetAttribute("Content") | Should -Be ([string][char]0xE921)
        $maximizeIcon.GetAttribute("Value") | Should -Be ([string][char]0xE922)
        $restoreIcon.GetAttribute("Value") | Should -Be ([string][char]0xE923)
        $closeButton.GetAttribute("Content") | Should -Be ([string][char]0xE8BB)
        $maximizeStyle.GetAttribute("BasedOn") | Should -Be "{StaticResource HoverButtonStyle}"
        [int]$themes.shared.CloseIconFontSize | Should -BeLessThan ([int]$themes.shared.SettingsIconFontSize)
    }
}

Describe "XAML and sync wiring" {
    It "wires generated config panels to existing target grids" {
        $xamlNames = @(Get-WinUtilXamlRuntimeNamedControls | ForEach-Object { $_.Name })
        $uiLines = Get-Content -Path $script:uiScriptPath
        $invalidTargets = New-Object System.Collections.Generic.List[string]

        foreach ($line in $uiLines) {
            if ($line.TrimStart().StartsWith("#")) {
                continue
            }

            $match = [regex]::Match(
                $line,
                'Invoke-WPFUIElements\s+-configVariable\s+\$sync\.configs\.([A-Za-z0-9_]+)\s+-targetGridName\s+"([^"]+)"'
            )
            if (-not $match.Success) {
                continue
            }

            $configName = $match.Groups[1].Value
            $targetGridName = $match.Groups[2].Value
            if (-not (Test-Path -Path (Join-Path $script:configRoot "$configName.json"))) {
                $invalidTargets.Add("$configName references missing config file")
            }

            if (-not (Test-WinUtilNameInSet -Name $targetGridName -Set $xamlNames)) {
                $invalidTargets.Add("$configName target grid '$targetGridName' was not found in XAML")
            }
        }

        if ($invalidTargets.Count -gt 0) {
            throw ($invalidTargets -join "`n")
        }
    }

    It "references only XAML, generated, or intentionally dynamic sync members" {
        $sourceText = Get-WinUtilSourceText
        $xamlNames = @(Get-WinUtilXamlRuntimeNamedControls | ForEach-Object { $_.Name })
        $generatedNames = @(Get-WinUtilGeneratedControlNames)
        $dynamicStateNames = @(
            "Form",
            "configs",
            "preferences",
            "runspace",
            "Buttons",
            "PSScriptRoot",
            "version",
            "IsLocalCompile",
            "winutildir",
            "logPath",
            "transcriptPath",
            "ActiveJob",
            "ActiveJobToken",
            "LastJobResult",
            # Intrinsic to the synchronized hashtable rather than WinUtil state; the job layer
            # locks on it to claim and release the active job slot
            "SyncRoot",
            "UIRunspace",
            "UIDispatchDelegate",
            "StepTimings",
            "LoggedErrors",
            "StartedAt",
            "SessionState",
            "TabWarmupQueue",
            "BackgroundQueues",
            "ConsoleProgressState",
            "LastInputAt",
            "ActiveShells",
            "RunspacePoolLock",
            "AssetRenderLock",
            "ShuttingDown",
            "ForceClose",
            "FinishInConsole",
            "PendingCloseWork",
            "StopWatchdogTimer",
            "IconFetchRunning",
            "selected",
            "selectedAppx",
            "selectedApps",
            "selectedTweaks",
            "selectedToggles",
            "currentTab",
            "selectedAppsStackPanel",
            "selectedAppsstackPanel",
            "selectedAppsPopup",
            "appPopup",
            "appPopupSelectedApp",
            "ItemsControl",
            "ImportInProgress",
            "ScriptsInstallPrograms",
            "keys",
            "ContainsKey",
            "GetEnumerator",
            "Remove",
            "logorender",
            "checkmarkrender",
            "warningrender",
            "InitializedTabs",
            "AppCategoryAutoExpanded",
            "RenderedAssetCache",
            "ToggleStatusCache",
            "InstallAppRenderQueue",
            "InstallAppEntriesRendered",
            "FontScaleFactor"
        )
        $allowedNames = @($xamlNames + $generatedNames + $dynamicStateNames) | Sort-Object -Unique
        $bracketReferences = @(
            [regex]::Matches($sourceText, '\$sync\[\s*["'']([A-Za-z_][A-Za-z0-9_]*)["'']\s*\]') |
                ForEach-Object { $_.Groups[1].Value }
        )
        $dotReferences = @(
            [regex]::Matches($sourceText, '\$sync\.([A-Za-z_][A-Za-z0-9_]*)') |
                ForEach-Object { $_.Groups[1].Value }
        )
        $literalReferences = @($bracketReferences + $dotReferences) | Sort-Object -Unique

        $invalidReferences = @(
            $literalReferences | Where-Object { -not (Test-WinUtilNameInSet -Name $_ -Set $allowedNames) }
        )
        if ($invalidReferences.Count -gt 0) {
            throw ($invalidReferences -join "`n")
        }
    }
}

Describe "WPF handler wiring" {
    It "calls only defined Invoke-WPF functions" {
        $sourceText = Get-WinUtilSourceText
        $functionNames = @(Get-WinUtilTopLevelFunctionNames)
        $invokedFunctions = @(
            [regex]::Matches($sourceText, '\b(Invoke-WPF[A-Za-z0-9]+)\b') |
                ForEach-Object { $_.Groups[1].Value }
        ) | Sort-Object -Unique

        $missingFunctions = @(
            $invokedFunctions | Where-Object { -not (Test-WinUtilNameInSet -Name $_ -Set $functionNames) }
        )
        if ($missingFunctions.Count -gt 0) {
            throw ($missingFunctions -join "`n")
        }
    }

    It "routes static WPF buttons through Invoke-WPFButton or explicit handlers" {
        $runtimeControls = @(Get-WinUtilXamlRuntimeNamedControls)
        $buttonControls = @(
            $runtimeControls |
                Where-Object { $_.Name -like "WPF*" -and $_.Type -in @("Button", "ToggleButton") }
        )
        $buttonSwitchNames = @(Get-WinUtilButtonSwitchNames)
        $uiScript = Get-Content -Path $script:uiScriptPath -Raw
        $unhandledButtons = New-Object System.Collections.Generic.List[string]

        foreach ($button in $buttonControls) {
            $hasSwitchHandler = (Test-WinUtilNameInSet -Name $button.Name -Set $buttonSwitchNames) -or $button.Name -like "WPFTab?BT"
            $escapedName = [regex]::Escape($button.Name)
            $explicitHandlerPattern = '\$sync\s*(?:\[\s*["'']' + $escapedName + '["'']\s*\]|\.' + $escapedName + ')\.Add_Click'
            $hasExplicitHandler = $uiScript -imatch $explicitHandlerPattern

            if (-not ($hasSwitchHandler -or $hasExplicitHandler)) {
                $unhandledButtons.Add($button.Name)
            }
        }

        if ($unhandledButtons.Count -gt 0) {
            throw ($unhandledButtons -join "`n")
        }
    }

    It "invokes existing WPF button names" {
        $sourceText = Get-WinUtilSourceText
        $xamlNames = @(Get-WinUtilXamlRuntimeNamedControls | ForEach-Object { $_.Name })
        $generatedNames = @(Get-WinUtilGeneratedControlNames)
        $validButtonNames = @($xamlNames + $generatedNames) | Sort-Object -Unique
        $buttonNames = @(
            [regex]::Matches($sourceText, 'Invoke-WPFButton\s+["'']([^"'']+)["'']') |
                ForEach-Object { $_.Groups[1].Value }
        ) | Sort-Object -Unique

        $missingButtons = @(
            $buttonNames | Where-Object { -not (Test-WinUtilNameInSet -Name $_ -Set $validButtonNames) }
        )
        if ($missingButtons.Count -gt 0) {
            throw ($missingButtons -join "`n")
        }
    }
}
