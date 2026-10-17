#===========================================================================
# Tests - Restore Point
#===========================================================================

BeforeAll {
    $script:repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
    . (Join-Path $script:repoRoot "functions\private\New-WinUtilRestorePoint.ps1")
    . (Join-Path $script:repoRoot "functions\private\Request-WinUtilRestorePoint.ps1")
    . (Join-Path $script:repoRoot "functions\private\Invoke-WinUtilRestorePointStep.ps1")
    . (Join-Path $script:repoRoot "functions\private\Measure-WinUtilStep.ps1")

    function Write-WinUtilLog {
        param($Message, $Level, $Component)
    }
    function Show-WinUtilMessage {
        param($Message, $Title, $Button, $Icon)
    }
    function Test-WinUtilUIAlive { }
}

Describe "Request-WinUtilRestorePoint" {
    BeforeEach {
        Mock Test-WinUtilUIAlive { $true }
    }

    It "maps <Answer> to <Expected>" -TestCases @(
        @{ Answer = "Yes"; Expected = $true }
        @{ Answer = "No"; Expected = $false }
        @{ Answer = "Cancel"; Expected = $null }
    ) {
        param($Answer, $Expected)
        Mock Show-WinUtilMessage { $Answer }

        Request-WinUtilRestorePoint -Subject "2 selected tweak(s)" | Should -Be $Expected
        Should -Invoke -CommandName Show-WinUtilMessage -Times 1 -Exactly -ParameterFilter {
            $Button -eq "YesNoCancel" -and $Message -like "*2 selected tweak(s)*"
        }
    }

    It "always takes one when there is no window to ask on" {
        Mock Test-WinUtilUIAlive { $false }
        Mock Show-WinUtilMessage { "No" }

        Request-WinUtilRestorePoint -Subject "tweaks" | Should -BeTrue
        Should -Invoke -CommandName Show-WinUtilMessage -Times 0 -Exactly
    }
}

Describe "Invoke-WinUtilRestorePointStep" {
    BeforeAll {
        $script:sync = @{}
    }

    BeforeEach {
        Mock Test-WinUtilUIAlive { $true }
        Mock Show-WinUtilMessage { "No" }
    }

    It "continues without asking when the restore point was created" {
        Mock New-WinUtilRestorePoint { $true }

        Invoke-WinUtilRestorePointStep | Should -BeTrue
        Should -Invoke -CommandName Show-WinUtilMessage -Times 0 -Exactly
    }

    It "stops when it failed and the user declines to go on" {
        Mock New-WinUtilRestorePoint { $false }

        Invoke-WinUtilRestorePointStep | Should -BeFalse
        Should -Invoke -CommandName Show-WinUtilMessage -Times 1 -Exactly -ParameterFilter { $Button -eq "YesNo" }
    }

    It "continues when it failed and the user chooses to go on" {
        Mock New-WinUtilRestorePoint { $false }
        Mock Show-WinUtilMessage { "Yes" }

        Invoke-WinUtilRestorePointStep | Should -BeTrue
    }

    It "continues with a warning in a headless run" {
        Mock New-WinUtilRestorePoint { $false }
        Mock Test-WinUtilUIAlive { $false }
        Mock Write-WinUtilLog { }

        Invoke-WinUtilRestorePointStep | Should -BeTrue
        Should -Invoke -CommandName Show-WinUtilMessage -Times 0 -Exactly
        Should -Invoke -CommandName Write-WinUtilLog -Times 1 -Exactly -ParameterFilter { $Level -eq "WARN" }
    }
}

Describe "New-WinUtilRestorePoint" {
    BeforeEach {
        Mock Write-WinUtilLog { }
        Mock Set-ItemProperty { }
        Mock Remove-ItemProperty { }
        Mock Get-ItemProperty { $null }
        Mock Invoke-CimMethod { [pscustomobject]@{ ReturnValue = 0 } }
    }

    It "enables System Protection and creates the restore point through WMI" {
        New-WinUtilRestorePoint -Description "Test point" | Should -BeTrue

        Should -Invoke -CommandName Invoke-CimMethod -Times 1 -Exactly -ParameterFilter {
            $ClassName -eq "SystemRestore" -and $MethodName -eq "Enable"
        }
        Should -Invoke -CommandName Invoke-CimMethod -Times 1 -Exactly -ParameterFilter {
            $ClassName -eq "SystemRestore" -and $MethodName -eq "CreateRestorePoint" -and $Arguments.Description -eq "Test point"
        }
    }

    It "removes the frequency override afterwards when there was none before" {
        New-WinUtilRestorePoint | Out-Null

        Should -Invoke -CommandName Set-ItemProperty -Times 1 -Exactly -ParameterFilter {
            $Name -eq "SystemRestorePointCreationFrequency" -and $Value -eq 0
        }
        Should -Invoke -CommandName Remove-ItemProperty -Times 1 -Exactly -ParameterFilter {
            $Name -eq "SystemRestorePointCreationFrequency"
        }
    }

    It "puts back the frequency value that was there before" {
        Mock Get-ItemProperty { [pscustomobject]@{ SystemRestorePointCreationFrequency = 1440 } }

        New-WinUtilRestorePoint | Out-Null

        Should -Invoke -CommandName Set-ItemProperty -Times 1 -Exactly -ParameterFilter {
            $Name -eq "SystemRestorePointCreationFrequency" -and $Value -eq 1440
        }
        Should -Invoke -CommandName Remove-ItemProperty -Times 0 -Exactly
    }

    It "returns false instead of throwing when Windows refuses" {
        Mock Invoke-CimMethod { [pscustomobject]@{ ReturnValue = 1 } } -ParameterFilter { $MethodName -eq "CreateRestorePoint" }

        New-WinUtilRestorePoint | Should -BeFalse
        Should -Invoke -CommandName Write-WinUtilLog -Times 1 -Exactly -ParameterFilter { $Level -eq "WARN" }
    }

    It "returns false when System Protection cannot be turned on" {
        Mock Invoke-CimMethod { throw "Access denied" } -ParameterFilter { $MethodName -eq "Enable" }

        New-WinUtilRestorePoint | Should -BeFalse
        Should -Invoke -CommandName Invoke-CimMethod -Times 0 -Exactly -ParameterFilter { $MethodName -eq "CreateRestorePoint" }
    }
}
