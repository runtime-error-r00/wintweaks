function Set-WinUtilPowerPlan {
    <#
    .SYNOPSIS
        Creates and activates the WinTweaks Performance power plan, or removes it

    .DESCRIPTION
        The plan is a copy of Balanced with the processor held at 100%, the disk never turned
        off, no sleep or hibernation timeout and the wireless adapter at maximum performance,
        on both mains and battery. Running it again reuses the existing plan instead of
        creating a second copy.

        With -Undo, Balanced is made active again and the plan is deleted.

    .PARAMETER Undo
        Switch back to Balanced and delete the plan.
    #>
    param(
        [switch]$Undo
    )

    $planName = "WinTweaks Performance"
    $balancedGuid = "381b4222-f694-41f0-9685-ff5bb260df2e"
    $guidPattern = '[0-9a-fA-F]{8}(?:-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}'

    $planGuid = $null
    foreach ($line in @(powercfg.exe /list)) {
        $match = [regex]::Match([string]$line, "($guidPattern)\s+\($([regex]::Escape($planName))\)")
        if ($match.Success) {
            $planGuid = $match.Groups[1].Value
            break
        }
    }

    if ($Undo) {
        powercfg.exe /setactive $balancedGuid | Out-Null
        if ($planGuid) {
            powercfg.exe /delete $planGuid | Out-Null
        }
        Write-WinUtilLog -Component "PowerPlan" -Message "Balanced power plan restored and '$planName' removed."
        return
    }

    if (-not $planGuid) {
        $duplicateOutput = (@(powercfg.exe /duplicatescheme $balancedGuid)) -join " "
        $match = [regex]::Match($duplicateOutput, $guidPattern)
        if (-not $match.Success) {
            throw "The '$planName' power plan could not be created: $duplicateOutput"
        }
        $planGuid = $match.Value
        powercfg.exe /changename $planGuid $planName "Created by WinTweaks" | Out-Null
    }

    $settings = @(
        @("SUB_DISK", "DISKIDLE", 0),
        @("SUB_SLEEP", "STANDBYIDLE", 0),
        @("SUB_SLEEP", "HIBERNATEIDLE", 0),
        @("SUB_PROCESSOR", "PROCTHROTTLEMIN", 100),
        @("SUB_PROCESSOR", "PROCTHROTTLEMAX", 100),
        # Wireless Adapter Settings > Power Saving Mode: Maximum Performance
        @("19cbb8fa-5279-450e-9fac-8a3d5fedd0c1", "12bbebe6-58d6-4636-95bb-3217ef867c1a", 0)
    )
    foreach ($setting in $settings) {
        powercfg.exe /setacvalueindex $planGuid $setting[0] $setting[1] $setting[2] | Out-Null
        powercfg.exe /setdcvalueindex $planGuid $setting[0] $setting[1] $setting[2] | Out-Null
    }

    powercfg.exe /setactive $planGuid | Out-Null
    if ($LASTEXITCODE -ne 0) {
        throw "The '$planName' power plan could not be activated (powercfg exit code $LASTEXITCODE)."
    }
    Write-WinUtilLog -Component "PowerPlan" -Message "'$planName' power plan created and activated."
}
