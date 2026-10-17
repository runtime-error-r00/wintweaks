#===========================================================================
# Tests - Work button routing

BeforeAll {
    $script:repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
    . (Join-Path $script:repoRoot "functions\public\Invoke-WPFButton.ps1")
    . (Join-Path $script:repoRoot "functions\private\Request-WinUtilRestorePoint.ps1")
    . (Join-Path $script:repoRoot "functions\private\Invoke-WinUtilRestorePointStep.ps1")

    function Start-WinUtilJob {
        param([string]$Name, [scriptblock]$ScriptBlock, [hashtable]$Parameters)
    }
    function Step-WinUtilJob {
        param([string]$Status, [int]$Percent, [string]$State, [string]$Overlay, [switch]$Hide)
    }
    function Write-WinUtilLog {
        param($Message, $Level, $Component)
    }
    function Write-WinUtilErrorRecord {
        param($ErrorRecord, $Component, $Context)
    }
    function Invoke-WPFFeatureInstall { }
    function Invoke-WPFUpdatessecurity { }
}

Describe "Work button preflight" {
    BeforeEach {
        $script:sync = [Hashtable]::Synchronized(@{
            ActiveJob = $null
            configs = @{
                feature = @{
                    WPFFeatureInstall = [pscustomobject]@{
                        Content = "Install Features"
                        function = "Invoke-WPFFeatureInstall"
                    }
                }
            }
            WPFUpdatessecurity = [pscustomobject]@{ Content = "Apply Recommended" }
        })
        $script:capturedJob = $null

        Mock Step-WinUtilJob { }
        Mock Write-WinUtilLog { }
        Mock Write-WinUtilErrorRecord { }
        Mock Invoke-WPFFeatureInstall { }
        Mock Invoke-WPFUpdatessecurity { }
        Mock Request-WinUtilRestorePoint { $true }
        Mock Invoke-WinUtilRestorePointStep { $true }
        Mock Start-WinUtilJob {
            $script:capturedJob = [pscustomobject]@{
                Name = $Name
                ScriptBlock = $ScriptBlock
                Parameters = $Parameters
            }
        }
    }

    AfterEach {
        Remove-Variable -Name sync -Scope Script -ErrorAction SilentlyContinue
        Remove-Variable -Name capturedJob -Scope Script -ErrorAction SilentlyContinue
    }

    It "lets feature installation validate its selection before starting a job" {
        Invoke-WPFButton -Button "WPFFeatureInstall"

        Should -Invoke Invoke-WPFFeatureInstall -Times 1 -Exactly
        Should -Invoke Start-WinUtilJob -Times 0 -Exactly
    }

    It "does not start the recommended update job when the restore point prompt is cancelled" {
        Mock Request-WinUtilRestorePoint { $null }

        Invoke-WPFButton -Button "WPFUpdatessecurity"

        Should -Invoke Request-WinUtilRestorePoint -Times 1 -Exactly
        Should -Invoke Start-WinUtilJob -Times 0 -Exactly
    }

    It "takes the restore point inside the job before applying the recommended profile" {
        Invoke-WPFButton -Button "WPFUpdatessecurity"

        Should -Invoke Start-WinUtilJob -Times 1 -Exactly -ParameterFilter {
            $Name -eq "Apply Recommended" -and $Parameters.CreateRestorePoint -eq $true
        }

        $jobParameters = $script:capturedJob.Parameters
        & $script:capturedJob.ScriptBlock @jobParameters

        Should -Invoke Invoke-WinUtilRestorePointStep -Times 1 -Exactly
        Should -Invoke Invoke-WPFUpdatessecurity -Times 1 -Exactly
    }

    It "skips the restore point when the user declines it" {
        Mock Request-WinUtilRestorePoint { $false }

        Invoke-WPFButton -Button "WPFUpdatessecurity"
        $jobParameters = $script:capturedJob.Parameters
        & $script:capturedJob.ScriptBlock @jobParameters

        Should -Invoke Invoke-WinUtilRestorePointStep -Times 0 -Exactly
        Should -Invoke Invoke-WPFUpdatessecurity -Times 1 -Exactly
    }

    It "applies nothing when the restore point step says to stop" {
        Mock Invoke-WinUtilRestorePointStep { $false }

        Invoke-WPFButton -Button "WPFUpdatessecurity"
        $jobParameters = $script:capturedJob.Parameters
        & $script:capturedJob.ScriptBlock @jobParameters

        Should -Invoke Invoke-WPFUpdatessecurity -Times 0 -Exactly
    }

    It "does not ask about a restore point for other work buttons" {
        Invoke-WPFButton -Button "WPFUpdatesdefault"

        Should -Invoke Request-WinUtilRestorePoint -Times 0 -Exactly
        Should -Invoke Start-WinUtilJob -Times 1 -Exactly -ParameterFilter { $Parameters.CreateRestorePoint -eq $false }
    }
}
