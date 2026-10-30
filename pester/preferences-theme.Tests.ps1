#===========================================================================
# Tests - Preferences and Themes
#===========================================================================

BeforeAll {
    $script:repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path

    # Theme application sets Thickness, CornerRadius and GridLength resources, so the real WPF
    # types have to be loaded here rather than left to whichever other test file happened to
    # load them first
    Add-Type -AssemblyName PresentationFramework
    Add-Type -AssemblyName PresentationCore
    Add-Type -AssemblyName WindowsBase

    if (-not ("Windows.Media.SolidColorBrush" -as [type])) {
        Add-Type @"
namespace Windows.Media
{
    public class SolidColorBrush
    {
        public object Value { get; private set; }

        public SolidColorBrush(object value)
        {
            Value = value;
        }

        public override string ToString()
        {
            return Value == null ? "" : Value.ToString();
        }
    }

    public struct Color
    {
        public byte R;
        public byte G;
        public byte B;

        public static Color FromRgb(byte r, byte g, byte b)
        {
            return new Color { R = r, G = g, B = b };
        }

        public override string ToString()
        {
            return string.Format("#{0:X2}{1:X2}{2:X2}", R, G, B);
        }
    }

    public class FontFamily
    {
        public string Value { get; private set; }

        public FontFamily(string value)
        {
            Value = value;
        }

        public override string ToString()
        {
            return Value;
        }
    }
}

namespace System.Windows
{
    public class CornerRadius
    {
        public double Value { get; private set; }

        public CornerRadius(double value)
        {
            Value = value;
        }

        public override string ToString()
        {
            return Value.ToString();
        }
    }

    public class GridLength
    {
        public double Value { get; private set; }

        public GridLength(double value)
        {
            Value = value;
        }

        public override string ToString()
        {
            return Value.ToString();
        }
    }

    public class Thickness
    {
        public double Left { get; private set; }
        public double Top { get; private set; }
        public double Right { get; private set; }
        public double Bottom { get; private set; }

        public Thickness(double uniformLength)
        {
            Left = uniformLength;
            Top = uniformLength;
            Right = uniformLength;
            Bottom = uniformLength;
        }

        public Thickness(double horizontal, double vertical)
        {
            Left = horizontal;
            Top = vertical;
            Right = horizontal;
            Bottom = vertical;
        }

        public Thickness(double left, double top, double right, double bottom)
        {
            Left = left;
            Top = top;
            Right = right;
            Bottom = bottom;
        }

        public override string ToString()
        {
            return string.Format("{0},{1},{2},{3}", Left, Top, Right, Bottom);
        }
    }
}
"@
    }

    . (Join-Path $script:repoRoot "functions\private\Invoke-WinutilThemeChange.ps1")

    function Test-WinUtilUIAlive { $null -ne $sync.Form -and $null -ne $sync.Form.Dispatcher }


    function Get-WinUtilToggleStatus {
        param($ToggleName)
        return $false
    }

    function script:New-WinUtilPreferencesTestRoot {
        $testRoot = Join-Path ([IO.Path]::GetTempPath()) "WinUtilPreferences_$([guid]::NewGuid())"
        New-Item -Path $testRoot -ItemType Directory -Force | Out-Null
        $testRoot
    }

    function script:New-WinUtilFakeThemeForm {
        [pscustomobject]@{
            Resources = @{}
        }
    }

    function script:New-WinUtilPreferenceSync {
        param(
            [hashtable]$Preferences = @{}
        )

        $script:sync = [Hashtable]::Synchronized(@{
            preferences = $Preferences
            configs = @{
                themes = Get-Content -Path (Join-Path $script:repoRoot "config\themes.json") -Raw | ConvertFrom-Json
            }
            Form = New-WinUtilFakeThemeForm
        })
        $global:sync = $script:sync
    }

    function script:Remove-WinUtilPreferenceGlobals {
        Remove-Variable -Name sync -Scope Global -ErrorAction SilentlyContinue
        Remove-Variable -Name winutildir -Scope Global -ErrorAction SilentlyContinue
    }
}

Describe "Invoke-WinutilThemeChange" {
    AfterEach {
        if ($script:testRoot -and (Test-Path $script:testRoot)) {
            Remove-Item -Path $script:testRoot -Recurse -Force -ErrorAction SilentlyContinue
        }
        $script:testRoot = $null
        Remove-WinUtilPreferenceGlobals
    }

    It "applies shared and dark theme resources without writing preferences" {
        $script:testRoot = New-WinUtilPreferencesTestRoot
        $global:winutildir = $script:testRoot
        New-WinUtilPreferenceSync

        Invoke-WinutilThemeChange

        $script:sync.Form.Resources.ContainsKey("FontFamily") | Should -BeTrue
        $script:sync.Form.Resources.ContainsKey("ButtonCornerRadius") | Should -BeTrue
        $script:sync.Form.Resources.ContainsKey("CBorderColor") | Should -BeTrue
        $script:sync.Form.Resources["MainBackgroundColor"].ToString() | Should -Be ([Windows.Media.SolidColorBrush]::new($script:sync.configs.themes.Dark.MainBackgroundColor)).ToString()

        Test-Path -Path (Join-Path $script:testRoot "preferences.ini") | Should -BeFalse
    }
}

Describe "Theme configuration" {
    It "contains resources with value shapes consumed by theme application" {
        $themes = Get-Content -Path (Join-Path $script:repoRoot "config\themes.json") -Raw | ConvertFrom-Json
        $invalidEntries = [System.Collections.Generic.List[string]]::new()

        foreach ($themeName in @("shared", "Dark")) {
            foreach ($property in $themes.$themeName.PSObject.Properties) {
                if ($property.Name -like "*Color" -and [string]$property.Value -notmatch '^(#[0-9A-Fa-f]{6}|Transparent)$') {
                    $invalidEntries.Add("$themeName.$($property.Name) should be a hex color or Transparent")
                }
                elseif ($property.Name -like "*Radius" -and [string]$property.Value -notmatch '^\d+(\.\d+)?$') {
                    $invalidEntries.Add("$themeName.$($property.Name) should be numeric")
                }
                elseif (($property.Name -like "*Thickness" -or $property.Name -like "*Margin") -and [string]$property.Value -notmatch '^\d+(\.\d+)?(,\d+(\.\d+)?){0,3}$') {
                    $invalidEntries.Add("$themeName.$($property.Name) should be one, two, or four numeric values")
                }
                elseif ($property.Name -like "*RowHeight*" -and [string]$property.Value -notmatch '^\d+(\.\d+)?$') {
                    $invalidEntries.Add("$themeName.$($property.Name) should be numeric")
                }
            }
        }

        if ($invalidEntries.Count -gt 0) {
            throw ($invalidEntries -join "`n")
        }
    }
}
