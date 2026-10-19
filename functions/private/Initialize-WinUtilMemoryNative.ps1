function Initialize-WinUtilMemoryNative {
    <#
        .SYNOPSIS
            Compiles the native memory calls the Memory Cleaner page uses, once per process

        .DESCRIPTION
            Add-Type compiles into the process, so every runspace sees the type once any of them
            has built it, and building it a second time fails. The wrappers only marshal: each
            returns the raw NTSTATUS or Win32 error code and the PowerShell side decides what it
            means.

            Information classes and structure layouts follow the public phnt headers (MIT) and
            the Win32 documentation on learn.microsoft.com:
              SystemMemoryListInformation            80   SYSTEM_MEMORY_LIST_COMMAND / SYSTEM_MEMORY_LIST_INFORMATION
              SystemCombinePhysicalMemoryInformation 130  MEMORY_COMBINE_INFORMATION_EX
              SystemRegistryReconciliationInformation 155 no buffer
            The system file cache is flushed with the documented SetSystemFileCacheSize instead
            of SystemFileCacheInformationEx (81).
    #>

    if ('WinUtilMemoryNative' -as [type]) {
        return
    }

    Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;

public static class WinUtilMemoryNative {
    public const int SystemMemoryListInformation = 80;
    public const int SystemCombinePhysicalMemoryInformation = 130;
    public const int SystemRegistryReconciliationInformation = 155;

    [StructLayout(LayoutKind.Sequential)]
    public struct MemoryStatusEx {
        public uint Length;
        public uint MemoryLoad;
        public ulong TotalPhys;
        public ulong AvailPhys;
        public ulong TotalPageFile;
        public ulong AvailPageFile;
        public ulong TotalVirtual;
        public ulong AvailVirtual;
        public ulong AvailExtendedVirtual;
    }

    [StructLayout(LayoutKind.Sequential)]
    public struct MemoryListInformation {
        public UIntPtr ZeroPageCount;
        public UIntPtr FreePageCount;
        public UIntPtr ModifiedPageCount;
        public UIntPtr ModifiedNoWritePageCount;
        public UIntPtr BadPageCount;
        [MarshalAs(UnmanagedType.ByValArray, SizeConst = 8)]
        public UIntPtr[] PageCountByPriority;
        [MarshalAs(UnmanagedType.ByValArray, SizeConst = 8)]
        public UIntPtr[] RepurposedPagesByPriority;
        public UIntPtr ModifiedPageCountPageFile;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct MemoryCombineInformationEx {
        public IntPtr Handle;
        public UIntPtr PagesCombined;
        public uint Flags;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct Luid {
        public uint LowPart;
        public int HighPart;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct TokenPrivileges {
        public uint PrivilegeCount;
        public Luid Luid;
        public uint Attributes;
    }

    [DllImport("ntdll.dll")]
    private static extern int NtSetSystemInformation(int infoClass, IntPtr info, int length);

    [DllImport("ntdll.dll")]
    private static extern int NtQuerySystemInformation(int infoClass, IntPtr info, int length, out int returnLength);

    [DllImport("ntdll.dll")]
    public static extern int RtlNtStatusToDosError(int status);

    [DllImport("kernel32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool GlobalMemoryStatusEx(ref MemoryStatusEx buffer);

    [DllImport("kernel32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool SetSystemFileCacheSize(UIntPtr minimum, UIntPtr maximum, uint flags);

    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern IntPtr OpenProcess(uint access, [MarshalAs(UnmanagedType.Bool)] bool inherit, int processId);

    [DllImport("kernel32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool K32EmptyWorkingSet(IntPtr process);

    [DllImport("kernel32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool CloseHandle(IntPtr handle);

    [DllImport("kernel32.dll")]
    private static extern IntPtr GetCurrentProcess();

    [DllImport("advapi32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool OpenProcessToken(IntPtr process, uint access, out IntPtr token);

    [DllImport("advapi32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool LookupPrivilegeValue(string systemName, string name, out Luid luid);

    [DllImport("advapi32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool AdjustTokenPrivileges(IntPtr token, [MarshalAs(UnmanagedType.Bool)] bool disableAll, ref TokenPrivileges newState, int bufferLength, IntPtr previousState, IntPtr returnLength);

    // Returns the Win32 error: 0 when enabled, 1300 (ERROR_NOT_ALL_ASSIGNED) when the token
    // does not hold the privilege at all
    public static int EnablePrivilege(string name) {
        const uint TokenAdjustPrivileges = 0x0020;
        const uint TokenQuery = 0x0008;
        const uint SePrivilegeEnabled = 0x00000002;

        IntPtr token;
        if (!OpenProcessToken(GetCurrentProcess(), TokenAdjustPrivileges | TokenQuery, out token)) {
            return Marshal.GetLastWin32Error();
        }
        try {
            Luid luid;
            if (!LookupPrivilegeValue(null, name, out luid)) {
                return Marshal.GetLastWin32Error();
            }
            TokenPrivileges privileges = new TokenPrivileges();
            privileges.PrivilegeCount = 1;
            privileges.Luid = luid;
            privileges.Attributes = SePrivilegeEnabled;
            if (!AdjustTokenPrivileges(token, false, ref privileges, 0, IntPtr.Zero, IntPtr.Zero)) {
                return Marshal.GetLastWin32Error();
            }
            // AdjustTokenPrivileges succeeds even when it assigned nothing; only the last error says so
            return Marshal.GetLastWin32Error();
        } finally {
            CloseHandle(token);
        }
    }

    public static int GetMemoryStatus(out MemoryStatusEx status) {
        status = new MemoryStatusEx();
        status.Length = (uint)Marshal.SizeOf(typeof(MemoryStatusEx));
        return GlobalMemoryStatusEx(ref status) ? 0 : Marshal.GetLastWin32Error();
    }

    // NTSTATUS
    public static int QueryMemoryLists(out MemoryListInformation information) {
        information = new MemoryListInformation();
        int size = Marshal.SizeOf(typeof(MemoryListInformation));
        IntPtr buffer = Marshal.AllocHGlobal(size);
        try {
            int returned;
            int status = NtQuerySystemInformation(SystemMemoryListInformation, buffer, size, out returned);
            if (status == 0) {
                information = (MemoryListInformation)Marshal.PtrToStructure(buffer, typeof(MemoryListInformation));
            }
            return status;
        } finally {
            Marshal.FreeHGlobal(buffer);
        }
    }

    // NTSTATUS. Commands: 2 empty working sets, 3 flush modified list, 4 purge standby list,
    // 5 purge low priority standby list
    public static int SendMemoryListCommand(int command) {
        IntPtr buffer = Marshal.AllocHGlobal(sizeof(int));
        try {
            Marshal.WriteInt32(buffer, command);
            return NtSetSystemInformation(SystemMemoryListInformation, buffer, sizeof(int));
        } finally {
            Marshal.FreeHGlobal(buffer);
        }
    }

    // NTSTATUS
    public static int CombinePhysicalMemory(out ulong pagesCombined) {
        pagesCombined = 0;
        MemoryCombineInformationEx information = new MemoryCombineInformationEx();
        int size = Marshal.SizeOf(typeof(MemoryCombineInformationEx));
        IntPtr buffer = Marshal.AllocHGlobal(size);
        try {
            Marshal.StructureToPtr(information, buffer, false);
            int status = NtSetSystemInformation(SystemCombinePhysicalMemoryInformation, buffer, size);
            if (status == 0) {
                information = (MemoryCombineInformationEx)Marshal.PtrToStructure(buffer, typeof(MemoryCombineInformationEx));
                pagesCombined = information.PagesCombined.ToUInt64();
            }
            return status;
        } finally {
            Marshal.FreeHGlobal(buffer);
        }
    }

    // NTSTATUS
    public static int ReconcileRegistry() {
        return NtSetSystemInformation(SystemRegistryReconciliationInformation, IntPtr.Zero, 0);
    }

    // Win32 error
    public static int FlushSystemFileCache() {
        UIntPtr flush = new UIntPtr(ulong.MaxValue);
        if (IntPtr.Size == 4) {
            flush = new UIntPtr(uint.MaxValue);
        }
        return SetSystemFileCacheSize(flush, flush, 0) ? 0 : Marshal.GetLastWin32Error();
    }

    // Win32 error
    public static int EmptyProcessWorkingSet(int processId) {
        const uint ProcessSetQuota = 0x0100;
        const uint ProcessQueryLimitedInformation = 0x1000;

        IntPtr process = OpenProcess(ProcessSetQuota | ProcessQueryLimitedInformation, false, processId);
        if (process == IntPtr.Zero) {
            return Marshal.GetLastWin32Error();
        }
        try {
            return K32EmptyWorkingSet(process) ? 0 : Marshal.GetLastWin32Error();
        } finally {
            CloseHandle(process);
        }
    }
}
'@
}
