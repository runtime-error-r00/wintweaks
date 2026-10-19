function Get-WinUtilAdvancedGroup {
    <#

    .SYNOPSIS
        Describes one optimization group of the Advanced page and the tweaks its Apply runs

    .DESCRIPTION
        A group is every Advanced entry in tweaks.json with the group's category, except
        drop-downs, which apply as soon as a value is chosen, and entries marked "standalone",
        which get their own buttons because they are too risky to apply as part of a bundle.

    .PARAMETER Group
        General, KeyboardMouse, GPU or CPU.

    #>
    param(
        [Parameter(Mandatory)]
        [ValidateSet("General", "KeyboardMouse", "GPU", "CPU")]
        [string]$Group
    )

    $groups = @{
        General = @{
            Title = "General System Optimizations"
            Category = "a__General System"
            Description = "Applies general optimizations in the registry, Windows settings, boot timers and more."
        }
        KeyboardMouse = @{
            Title = "Keyboard and Mouse Optimizations"
            Category = "b__Keyboard and Mouse"
            Description = "Lowers input latency: no mouse acceleration, fastest key repeat, high priority for input handling and USB devices that never go to sleep."
        }
        GPU = @{
            Title = "GPU Optimizations"
            Category = "c__GPU"
            Description = "Applies driver settings for the graphics cards found in this PC. Settings for a vendor that is not in this PC are skipped."
        }
        CPU = @{
            Title = "CPU Optimizations"
            Category = "d__CPU"
            Description = "Keeps every CPU core awake at full speed on the active power plan. Do not apply this on a PC with overheating issues."
        }
    }

    $definition = $groups[$Group]
    $tweaks = @(
        (Get-WinUtilTabTweaks -Tab "Advanced").PSObject.Properties |
            Where-Object { $_.Value.category -eq $definition.Category -and -not $_.Value.Type -and -not $_.Value.standalone } |
            ForEach-Object Name
    )

    [pscustomobject]@{
        Name = $Group
        Title = $definition.Title
        Description = $definition.Description
        Category = $definition.Category
        Tweaks = $tweaks
    }
}
