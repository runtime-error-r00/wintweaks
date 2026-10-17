#===========================================================================
# Tests - Info icon tooltip
#===========================================================================

BeforeAll {
    $script:repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
    Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase
    . (Join-Path $script:repoRoot "functions\private\New-WinUtilInfoToolTip.ps1")
}

Describe "New-WinUtilInfoToolTip" {
    It "shows the title, the description and the risk line in that order" {
        $panel = New-WinUtilInfoToolTip -Title "Telemetry - Disable" -Description "Turns off diagnostic data." -Risk "medium"

        $panel | Should -BeOfType [System.Windows.Controls.StackPanel]
        @($panel.Children).Count | Should -Be 3
        $panel.Children[0].Text | Should -Be "Telemetry - Disable"
        $panel.Children[1].Text | Should -Be "Turns off diagnostic data."
        $panel.Children[2].Text | Should -BeLike "*Medium risk*"
    }

    It "leaves out the risk line for an entry without a rating" {
        $panel = New-WinUtilInfoToolTip -Title "WSL - Enable" -Description "Installs WSL."

        @($panel.Children).Count | Should -Be 2
    }

    It "ignores a rating it does not know" {
        $panel = New-WinUtilInfoToolTip -Title "Example" -Description "Text" -Risk "extreme"

        @($panel.Children).Count | Should -Be 2
    }

    It "keeps the window's label background off the tooltip text" {
        $panel = New-WinUtilInfoToolTip -Title "Example" -Description "Text" -Risk "low"

        foreach ($block in $panel.Children) {
            $block.Background | Should -Be ([System.Windows.Media.Brushes]::Transparent)
        }
    }
}

Describe "Tweak rows" {
    It "give every checkbox tweak a description for its info icon" {
        $tweaks = Get-Content -Path (Join-Path $script:repoRoot "config\tweaks.json") -Raw | ConvertFrom-Json
        $missing = @(
            $tweaks.PSObject.Properties |
                Where-Object { -not $_.Value.Type -and [string]::IsNullOrWhiteSpace($_.Value.Description) } |
                ForEach-Object { $_.Name }
        )

        $missing | Should -BeNullOrEmpty
    }
}
