function Get-WinUtilMemoryAreas {
    <#
        .SYNOPSIS
            Lists the memory areas the Memory Cleaner can clean, in the order they are cleaned

        .DESCRIPTION
            Working sets go first so the pages they release are on the modified and standby
            lists when those are flushed and purged. Measure says which figure shows what the
            area released: Used, Modified, Standby or Combined, or None when it frees no memory
            itself.

        .PARAMETER Build
            Windows build number to check MinimumBuild against. Defaults to the running system.
    #>
    param(
        [int]$Build = (Get-WinUtilWindowsBuild)
    )

    $areas = @(
        @{ Key = "ProcessWorkingSets"; Label = "Process working sets"; Measure = "Used"; MinimumBuild = 0; Default = $true
           Description = "Moves pages that running programs are not using out of their working sets." },
        @{ Key = "SystemFileCache"; Label = "System file cache"; Measure = "Used"; MinimumBuild = 0; Default = $true
           Description = "Empties the working set of the system file cache." },
        @{ Key = "ModifiedPageList"; Label = "Modified page list"; Measure = "Modified"; MinimumBuild = 0; Default = $true
           Description = "Writes changed pages to disk so they can be reused." },
        @{ Key = "StandbyListLowPriority"; Label = "Standby list (low priority)"; Measure = "Standby"; MinimumBuild = 0; Default = $true
           Description = "Frees cached pages Windows considers least likely to be used again." },
        @{ Key = "StandbyList"; Label = "Standby list"; Measure = "Standby"; MinimumBuild = 0; Default = $true
           Description = "Frees all cached pages. Programs may load more slowly until the cache is rebuilt." },
        @{ Key = "CombinedPageList"; Label = "Combined page list"; Measure = "Combined"; MinimumBuild = 9600; Default = $true
           Description = "Merges identical pages of memory into one shared copy." },
        @{ Key = "RegistryCache"; Label = "Registry cache"; Measure = "None"; MinimumBuild = 9600; Default = $false
           Description = "Writes pending registry changes to disk." }
    )

    foreach ($area in $areas) {
        [pscustomobject]@{
            Key          = $area.Key
            Label        = $area.Label
            Description  = $area.Description
            Measure      = $area.Measure
            MinimumBuild = $area.MinimumBuild
            Default      = $area.Default
            Supported    = $Build -ge $area.MinimumBuild
        }
    }
}

function Get-WinUtilWindowsBuild {
    <#
        .SYNOPSIS
            Returns the Windows build number, or 0 when it cannot be read
    #>

    try {
        return [int](Get-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion" -Name CurrentBuildNumber -ErrorAction Stop).CurrentBuildNumber
    } catch {
        return [Environment]::OSVersion.Version.Build
    }
}
