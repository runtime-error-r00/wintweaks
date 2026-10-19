function Get-WinUtilMemorySnapshot {
    <#
        .SYNOPSIS
            Reads physical memory use and the size of the standby and modified page lists

        .DESCRIPTION
            Every figure is in bytes. Standby, Modified and Free come from the kernel's page
            lists and are $null when the lists cannot be read; the rest come from
            GlobalMemoryStatusEx. Available includes standby pages, which is why purging the
            standby list does not move it.
    #>

    Initialize-WinUtilMemoryNative

    $status = New-Object WinUtilMemoryNative+MemoryStatusEx
    $statusError = [WinUtilMemoryNative]::GetMemoryStatus([ref]$status)
    if ($statusError -ne 0) {
        throw "Could not read memory status. $(Format-WinUtilNativeError -Win32Error $statusError)"
    }

    $snapshot = [ordered]@{
        TotalBytes     = [double]$status.TotalPhys
        AvailableBytes = [double]$status.AvailPhys
        UsedBytes      = [double]($status.TotalPhys - $status.AvailPhys)
        LoadPercent    = [int]$status.MemoryLoad
        FreeBytes      = $null
        StandbyBytes   = $null
        ModifiedBytes  = $null
    }

    $lists = New-Object WinUtilMemoryNative+MemoryListInformation
    if ([WinUtilMemoryNative]::QueryMemoryLists([ref]$lists) -eq 0) {
        $pageSize = [double][Environment]::SystemPageSize
        $standbyPages = 0.0
        foreach ($count in $lists.PageCountByPriority) {
            $standbyPages += $count.ToUInt64()
        }
        $snapshot.FreeBytes = ($lists.ZeroPageCount.ToUInt64() + $lists.FreePageCount.ToUInt64()) * $pageSize
        $snapshot.StandbyBytes = $standbyPages * $pageSize
        $snapshot.ModifiedBytes = $lists.ModifiedPageCount.ToUInt64() * $pageSize
    }

    return [pscustomobject]$snapshot
}
