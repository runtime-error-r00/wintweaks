function Enable-WinUtilPrivilege {
    <#
        .SYNOPSIS
            Enables a privilege on WinUtil's own process token, throwing when it cannot

        .DESCRIPTION
            An administrator token holds the memory privileges but keeps them disabled until
            asked. ERROR_NOT_ALL_ASSIGNED means the token does not hold the privilege at all,
            which is reported as such rather than as a raw code.

        .PARAMETER Name
            Privilege constant name, for example SeProfileSingleProcessPrivilege.
    #>
    param(
        [Parameter(Mandatory)]
        [string]$Name
    )

    Initialize-WinUtilMemoryNative

    $errorCode = [WinUtilMemoryNative]::EnablePrivilege($Name)
    if ($errorCode -eq 1300) {
        throw "$Name is not held by this account. Run WinTweaks as an administrator."
    }
    if ($errorCode -ne 0) {
        throw "Could not enable $Name. $(Format-WinUtilNativeError -Win32Error $errorCode)"
    }
}

function Format-WinUtilNativeError {
    <#
        .SYNOPSIS
            Turns an NTSTATUS or Win32 error code into a sentence with the code alongside it

        .PARAMETER NtStatus
            NTSTATUS returned by an Nt* call. Translated through RtlNtStatusToDosError.

        .PARAMETER Win32Error
            Win32 error code, for example from GetLastError.
    #>
    param(
        [Parameter(Mandatory, ParameterSetName = "NtStatus")]
        [int]$NtStatus,

        [Parameter(Mandatory, ParameterSetName = "Win32")]
        [int]$Win32Error
    )

    if ($PSCmdlet.ParameterSetName -eq "NtStatus") {
        # STATUS_INVALID_INFO_CLASS and STATUS_NOT_IMPLEMENTED: the kernel does not know the request
        if ($NtStatus -in @(0xC0000003, 0xC0000002)) {
            return "Not supported by this version of Windows (NTSTATUS 0x{0:X8})." -f $NtStatus
        }
        Initialize-WinUtilMemoryNative
        $message = ([System.ComponentModel.Win32Exception]::new([WinUtilMemoryNative]::RtlNtStatusToDosError($NtStatus))).Message
        return "$message (NTSTATUS 0x$($NtStatus.ToString('X8')))"
    }

    $message = ([System.ComponentModel.Win32Exception]::new($Win32Error)).Message
    return "$message (Win32 error $Win32Error)"
}
