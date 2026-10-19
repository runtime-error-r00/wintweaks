function Invoke-WinUtilMemoryClean {
    <#
        .SYNOPSIS
            Cleans the chosen memory areas in order and returns a report of what each released

        .DESCRIPTION
            Each area runs on its own: a failure is logged and recorded in the report, and the
            next area still runs. Meant for a job body, so it reports progress through
            Step-WinUtilJob and never touches the interface.

        .PARAMETER Areas
            Keys from Get-WinUtilMemoryAreas. Unknown keys are ignored.
    #>
    param(
        [string[]]$Areas = @()
    )

    Initialize-WinUtilMemoryNative

    $selected = @(foreach ($area in (Get-WinUtilMemoryAreas)) { if ($Areas -contains $area.Key) { $area } })
    if ($selected.Count -eq 0) {
        Write-WinUtilLog -Level "WARN" -Component "MemoryCleaner" -Message "No memory areas selected, nothing to clean."
        return Get-WinUtilMemoryCleanReport
    }

    $firstSnapshot = Get-WinUtilMemorySnapshot
    $snapshot = $firstSnapshot
    $results = [System.Collections.Generic.List[object]]::new()
    $index = 0

    foreach ($area in $selected) {
        Step-WinUtilJob -Status "Cleaning $($area.Label)" -Percent ([int](100 * $index / $selected.Count))
        $index++

        $result = [ordered]@{
            Key = $area.Key; Label = $area.Label; Measure = $area.Measure
            Status = "Cleaned"; Message = $null; CombinedBytes = $null
            Before = $snapshot; After = $snapshot
        }

        if (-not $area.Supported) {
            $result.Status = "Unsupported"
            Write-WinUtilLog -Level "WARN" -Component "MemoryCleaner" -Message "$($area.Label) needs Windows build $($area.MinimumBuild) or later, skipped."
            $results.Add([pscustomobject]$result)
            continue
        }

        try {
            $outcome = Invoke-WinUtilMemoryArea -Key $area.Key
            if ($outcome) {
                $result.Message = $outcome.Message
                $result.CombinedBytes = $outcome.CombinedBytes
            }
        } catch {
            $result.Status = "Failed"
            $result.Message = $_.Exception.Message
            Write-WinUtilLog -Level "ERROR" -Component "MemoryCleaner" -Message "$($area.Label) failed: $($_.Exception.Message)"
        }

        $snapshot = Get-WinUtilMemorySnapshot
        $result.After = $snapshot
        $results.Add([pscustomobject]$result)
    }

    $report = Get-WinUtilMemoryCleanReport -Results $results.ToArray() -Before $firstSnapshot -After $snapshot
    foreach ($line in (Format-WinUtilMemoryCleanReport -Report $report)) {
        Write-WinUtilLog -Component "MemoryCleaner" -Message $line
    }
    return $report
}

function Invoke-WinUtilMemoryArea {
    <#
        .SYNOPSIS
            Cleans one memory area, throwing a readable message when Windows refuses

        .OUTPUTS
            Nothing, or an object with Message and CombinedBytes for the report.
    #>
    param(
        [Parameter(Mandatory)]
        [string]$Key
    )

    switch ($Key) {
        "ProcessWorkingSets" {
            Enable-WinUtilPrivilege -Name "SeProfileSingleProcessPrivilege"
            $status = [WinUtilMemoryNative]::SendMemoryListCommand(2)
            if ($status -eq 0) { return }

            # The per-process path reaches everything the system-wide call would, only slower
            Write-WinUtilLog -Level "WARN" -Component "MemoryCleaner" -Message "System-wide working set trim refused: $(Format-WinUtilNativeError -NtStatus $status) Emptying processes one at a time instead."
            return Clear-WinUtilProcessWorkingSets
        }
        "SystemFileCache" {
            Enable-WinUtilPrivilege -Name "SeIncreaseQuotaPrivilege"
            $errorCode = [WinUtilMemoryNative]::FlushSystemFileCache()
            if ($errorCode -ne 0) { throw (Format-WinUtilNativeError -Win32Error $errorCode) }
        }
        "ModifiedPageList" { Invoke-WinUtilMemoryListCommand -Command 3 }
        "StandbyListLowPriority" { Invoke-WinUtilMemoryListCommand -Command 5 }
        "StandbyList" { Invoke-WinUtilMemoryListCommand -Command 4 }
        "CombinedPageList" {
            Enable-WinUtilPrivilege -Name "SeProfileSingleProcessPrivilege"
            $pages = [uint64]0
            $status = [WinUtilMemoryNative]::CombinePhysicalMemory([ref]$pages)
            if ($status -ne 0) { throw (Format-WinUtilNativeError -NtStatus $status) }
            return [pscustomobject]@{
                Message = "$pages pages combined"
                CombinedBytes = [double]$pages * [Environment]::SystemPageSize
            }
        }
        "RegistryCache" {
            $status = [WinUtilMemoryNative]::ReconcileRegistry()
            if ($status -ne 0) { throw (Format-WinUtilNativeError -NtStatus $status) }
        }
        default { throw "Unknown memory area '$Key'." }
    }
}

function Invoke-WinUtilMemoryListCommand {
    <#
        .SYNOPSIS
            Sends one SYSTEM_MEMORY_LIST_COMMAND to the kernel
    #>
    param(
        [Parameter(Mandatory)]
        [int]$Command
    )

    Enable-WinUtilPrivilege -Name "SeProfileSingleProcessPrivilege"
    $status = [WinUtilMemoryNative]::SendMemoryListCommand($Command)
    if ($status -ne 0) { throw (Format-WinUtilNativeError -NtStatus $status) }
}

function Clear-WinUtilProcessWorkingSets {
    <#
        .SYNOPSIS
            Empties the working set of every process, one at a time

        .DESCRIPTION
            Protected processes and ones that exit mid-way cannot be opened, which is expected
            and counted rather than treated as failure. The area fails only when no process at
            all could be emptied.
    #>

    # Without it, processes running under other accounts cannot be opened. Not fatal: the
    # current user's processes can still be emptied.
    try {
        Enable-WinUtilPrivilege -Name "SeDebugPrivilege"
    } catch {
        Write-WinUtilLog -Level "WARN" -Component "MemoryCleaner" -Message "$($_.Exception.Message) Only processes WinTweaks can open will be emptied."
    }

    $emptied = 0

    $refused = 0
    foreach ($process in (Get-Process)) {
        # The Idle and System processes have no working set that can be opened
        if ($process.Id -in @(0, 4)) { continue }

        if ([WinUtilMemoryNative]::EmptyProcessWorkingSet($process.Id) -eq 0) {
            $emptied++
        } else {
            $refused++
        }
    }

    if ($emptied -eq 0) {
        throw "No process working set could be emptied ($refused refused access)."
    }
    return [pscustomobject]@{
        Message = "$emptied processes emptied, $refused protected or exited"
        CombinedBytes = $null
    }
}
