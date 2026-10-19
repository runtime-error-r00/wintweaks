function Get-WinUtilMemoryCleanReport {
    <#
        .SYNOPSIS
            Works out how much each cleaned area released and the totals before and after

        .DESCRIPTION
            Each area is measured on the figure it acts on, because one figure cannot show them
            all: emptying working sets lowers memory in use but moves the pages to the standby
            list, and purging the standby list frees pages that Windows was already counting as
            available. A figure that grew counts as nothing released, not a negative amount.

        .PARAMETER Results
            One entry per area from Invoke-WinUtilMemoryClean: Key, Label, Measure, Status,
            Message, Before, After and, for the combined page list, CombinedBytes.

        .PARAMETER Before
            Snapshot from before the first area.

        .PARAMETER After
            Snapshot from after the last area.
    #>
    param(
        [object[]]$Results = @(),
        $Before,
        $After
    )

    $areas = foreach ($result in $Results) {
        $freed = $null
        if ($result.Status -eq "Cleaned") {
            $freed = Measure-WinUtilMemoryAreaFreed -Measure $result.Measure -Before $result.Before -After $result.After -CombinedBytes $result.CombinedBytes
        }
        [pscustomobject]@{
            Key        = $result.Key
            Label      = $result.Label
            Status     = $result.Status
            Message    = $result.Message
            FreedBytes = $freed
        }
    }
    $areas = @($areas)

    # Areas pass the same pages along (a trimmed working set lands on the standby list, which
    # the next area purges), so adding them up counts pages twice. Growth of the free list is
    # what was actually released; the sum stands in only when the lists could not be read.
    $totalFreed = 0.0
    if ($null -ne $Before -and $null -ne $After -and $null -ne $Before.FreeBytes -and $null -ne $After.FreeBytes) {
        $totalFreed = [Math]::Max(0.0, [double]$After.FreeBytes - [double]$Before.FreeBytes)
    } else {
        foreach ($area in $areas) {
            if ($null -ne $area.FreedBytes) { $totalFreed += $area.FreedBytes }
        }
    }

    return [pscustomobject]@{
        Before          = $Before
        After           = $After
        Areas           = $areas
        TotalFreedBytes = $totalFreed
        FailedCount     = @($areas | Where-Object { $_.Status -eq "Failed" }).Count
    }
}

function Measure-WinUtilMemoryAreaFreed {
    <#
        .SYNOPSIS
            Bytes one area released, from the snapshots taken either side of it

        .PARAMETER Measure
            Used, Modified, Standby or Combined, from Get-WinUtilMemoryAreas.

        .PARAMETER CombinedBytes
            Bytes the kernel reported combining. Used only when Measure is Combined.
    #>
    param(
        [string]$Measure,
        $Before,
        $After,
        $CombinedBytes
    )

    if ($Measure -eq "None") {
        return $null
    }
    if ($Measure -eq "Combined") {
        if ($null -eq $CombinedBytes) { return 0.0 }
        return [Math]::Max(0.0, [double]$CombinedBytes)
    }

    $property = switch ($Measure) {
        "Used" { "UsedBytes" }
        "Modified" { "ModifiedBytes" }
        "Standby" { "StandbyBytes" }
        default { throw "Unknown memory measure '$Measure'." }
    }

    if ($null -eq $Before -or $null -eq $After -or $null -eq $Before.$property -or $null -eq $After.$property) {
        return $null
    }
    return [Math]::Max(0.0, [double]$Before.$property - [double]$After.$property)
}

function Format-WinUtilMemorySize {
    <#
        .SYNOPSIS
            Formats a byte count as MB, or GB from 10 GB up, or "n/a" when unknown
    #>
    param($Bytes)

    if ($null -eq $Bytes) { return "n/a" }
    $megabytes = [double]$Bytes / 1MB
    if ($megabytes -ge 10240) {
        return "{0:N1} GB" -f ($megabytes / 1024)
    }
    return "{0:N0} MB" -f $megabytes
}

function Format-WinUtilMemoryCleanReport {
    <#
        .SYNOPSIS
            Writes a clean report as the lines shown on the page and in the log

        .PARAMETER Report
            Output of Get-WinUtilMemoryCleanReport.
    #>
    param(
        [Parameter(Mandatory)]
        $Report
    )

    $lines = [System.Collections.Generic.List[string]]::new()
    foreach ($area in $Report.Areas) {
        $line = switch ($area.Status) {
            "Cleaned" {
                if ($null -eq $area.FreedBytes) { "$($area.Label): done" } else { "$($area.Label): $(Format-WinUtilMemorySize $area.FreedBytes) released" }
            }
            "Failed" { "$($area.Label): failed - $($area.Message)" }
            "Unsupported" { "$($area.Label): not supported on this Windows version" }
            default { "$($area.Label): $($area.Status)" }
        }
        if ($area.Status -eq "Cleaned" -and $area.Message) {
            $line += " ($($area.Message))"
        }
        $lines.Add($line)
    }

    if ($Report.Before -and $Report.After) {
        $lines.Add("In use: $(Format-WinUtilMemorySize $Report.Before.UsedBytes) -> $(Format-WinUtilMemorySize $Report.After.UsedBytes)")
        $lines.Add("Standby: $(Format-WinUtilMemorySize $Report.Before.StandbyBytes) -> $(Format-WinUtilMemorySize $Report.After.StandbyBytes)")
        $lines.Add("Modified: $(Format-WinUtilMemorySize $Report.Before.ModifiedBytes) -> $(Format-WinUtilMemorySize $Report.After.ModifiedBytes)")
        $lines.Add("Free: $(Format-WinUtilMemorySize $Report.Before.FreeBytes) -> $(Format-WinUtilMemorySize $Report.After.FreeBytes)")
    }
    $lines.Add("Total released: $(Format-WinUtilMemorySize $Report.TotalFreedBytes)")
    return , $lines.ToArray()
}
