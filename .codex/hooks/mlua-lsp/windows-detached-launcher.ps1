# Read launch details as UTF-8 JSON, without putting arguments into PowerShell code.
$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = New-Object System.Text.UTF8Encoding($false)

try {
    $reader = New-Object System.IO.StreamReader(
        [Console]::OpenStandardInput(), [System.Text.Encoding]::UTF8)
    $request = ConvertFrom-Json -InputObject $reader.ReadToEnd()
    if ([string]::IsNullOrWhiteSpace($request.executable) -or
        [string]::IsNullOrWhiteSpace($request.commandLine)) {
        throw 'Missing executable or command line for the Windows LSP launcher.'
    }

    Add-Type -TypeDefinition @'
using System;
using System.ComponentModel;
using System.Runtime.InteropServices;
using System.Text;

namespace MswHooks {
    public static class DetachedProcess {
        private const uint CREATE_BREAKAWAY_FROM_JOB = 0x01000000;
        private const uint CREATE_NO_WINDOW = 0x08000000;
        private const uint EXTENDED_STARTUPINFO_PRESENT = 0x00080000;
        private const uint STARTF_USESTDHANDLES = 0x00000100;
        private static readonly IntPtr INVALID_HANDLE_VALUE = new IntPtr(-1);

        [StructLayout(LayoutKind.Sequential)]
        private struct SECURITY_ATTRIBUTES {
            public uint nLength;
            public IntPtr lpSecurityDescriptor;
            [MarshalAs(UnmanagedType.Bool)] public bool bInheritHandle;
        }

        [StructLayout(LayoutKind.Sequential)]
        private struct STARTUPINFO {
            public uint cb;
            public IntPtr lpReserved, lpDesktop, lpTitle;
            public uint dwX, dwY, dwXSize, dwYSize, dwXCountChars, dwYCountChars;
            public uint dwFillAttribute, dwFlags;
            public ushort wShowWindow, cbReserved2;
            public IntPtr lpReserved2, hStdInput, hStdOutput, hStdError;
        }

        [StructLayout(LayoutKind.Sequential)]
        private struct STARTUPINFOEX {
            public STARTUPINFO StartupInfo;
            public IntPtr lpAttributeList;
        }

        [StructLayout(LayoutKind.Sequential)]
        private struct PROCESS_INFORMATION {
            public IntPtr hProcess, hThread;
            public uint dwProcessId, dwThreadId;
        }

        [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
        private static extern IntPtr CreateFileW(string name, uint access, uint share,
            ref SECURITY_ATTRIBUTES security, uint disposition, uint attributes,
            IntPtr template);

        [DllImport("kernel32.dll", SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool InitializeProcThreadAttributeList(IntPtr list,
            int count, uint flags, ref IntPtr size);

        [DllImport("kernel32.dll", SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool UpdateProcThreadAttribute(IntPtr list,
            uint flags, UIntPtr attribute, IntPtr value, UIntPtr size,
            IntPtr previousValue, IntPtr returnSize);

        [DllImport("kernel32.dll")]
        private static extern void DeleteProcThreadAttributeList(IntPtr list);

        [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool CreateProcessW(string application,
            StringBuilder commandLine, IntPtr processSecurity, IntPtr threadSecurity,
            [MarshalAs(UnmanagedType.Bool)] bool inheritHandles, uint flags,
            IntPtr environment, string directory, ref STARTUPINFOEX startup,
            out PROCESS_INFORMATION process);

        [DllImport("kernel32.dll")]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool CloseHandle(IntPtr handle);

        private static Win32Exception Failure(string operation) {
            int code = Marshal.GetLastWin32Error();
            return new Win32Exception(code, operation + " (Win32 " + code + "): " +
                new Win32Exception(code).Message);
        }

        private static void Check(bool succeeded, string operation) {
            if (!succeeded) throw Failure(operation);
        }

        public static uint Start(string executable, string commandLine, string directory) {
            IntPtr nul = INVALID_HANDLE_VALUE;
            IntPtr attributes = IntPtr.Zero;
            IntPtr handles = IntPtr.Zero;
            bool attributesInitialized = false;
            PROCESS_INFORMATION process = new PROCESS_INFORMATION();
            try {
                SECURITY_ATTRIBUTES security = new SECURITY_ATTRIBUTES();
                security.nLength = (uint)Marshal.SizeOf(typeof(SECURITY_ATTRIBUTES));
                security.bInheritHandle = true;
                nul = CreateFileW("NUL", 0xC0000000, 3, ref security, 3, 0x80, IntPtr.Zero);
                if (nul == INVALID_HANDLE_VALUE)
                    throw Failure("Open NUL");

                IntPtr size = IntPtr.Zero;
                InitializeProcThreadAttributeList(IntPtr.Zero, 1, 0, ref size);
                if (size == IntPtr.Zero)
                    throw Failure("Size handle list");
                attributes = Marshal.AllocHGlobal(size);
                Check(InitializeProcThreadAttributeList(attributes, 1, 0, ref size),
                    "Initialize handle list");
                attributesInitialized = true;
                handles = Marshal.AllocHGlobal(IntPtr.Size);
                Marshal.WriteIntPtr(handles, nul);
                // Only NUL can be inherited. Hook/PowerShell pipes are excluded.
                Check(UpdateProcThreadAttribute(attributes, 0, new UIntPtr(0x00020002),
                    handles, new UIntPtr((uint)IntPtr.Size), IntPtr.Zero, IntPtr.Zero),
                    "Set inherited handles");

                STARTUPINFOEX startup = new STARTUPINFOEX();
                startup.StartupInfo.cb = (uint)Marshal.SizeOf(typeof(STARTUPINFOEX));
                startup.StartupInfo.dwFlags = STARTF_USESTDHANDLES;
                startup.StartupInfo.hStdInput = nul;
                startup.StartupInfo.hStdOutput = nul;
                startup.StartupInfo.hStdError = nul;
                startup.lpAttributeList = attributes;
                // Node detached/unref do not provide this Job breakaway flag.
                Check(CreateProcessW(executable, new StringBuilder(commandLine),
                    IntPtr.Zero, IntPtr.Zero, true,
                    CREATE_BREAKAWAY_FROM_JOB | CREATE_NO_WINDOW | EXTENDED_STARTUPINFO_PRESENT,
                    IntPtr.Zero, directory, ref startup, out process),
                    "Create independent LSP process");
                return process.dwProcessId;
            } finally {
                if (process.hThread != IntPtr.Zero) CloseHandle(process.hThread);
                if (process.hProcess != IntPtr.Zero) CloseHandle(process.hProcess);
                if (attributesInitialized) DeleteProcThreadAttributeList(attributes);
                if (attributes != IntPtr.Zero) Marshal.FreeHGlobal(attributes);
                if (handles != IntPtr.Zero) Marshal.FreeHGlobal(handles);
                if (nul != INVALID_HANDLE_VALUE) CloseHandle(nul);
            }
        }
    }
}
'@

    $executable = [string]$request.executable
    if (-not [System.IO.Path]::IsPathRooted($executable)) {
        $executable = (Get-Command $executable -CommandType Application -ErrorAction Stop).Source
    }
    $processId = [MswHooks.DetachedProcess]::Start(
        $executable, [string]$request.commandLine, [string]$request.workingDirectory)
    [Console]::Out.WriteLine((ConvertTo-Json -Compress -InputObject @{ pid = $processId }))
} catch {
    [Console]::Error.WriteLine($_.Exception.GetBaseException().Message)
    exit 1
}
