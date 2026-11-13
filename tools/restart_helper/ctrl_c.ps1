# ctrl_c.ps1 <process id>: sends Ctrl+C to a console program (the local dedicated server), the same as pressing
# Ctrl+C in its window, so it saves the world and stops. Run as its own hidden process by restart_helper.ps1: it
# leaves its own console and joins the server's for a moment. Exit code 0: sent.
param([int]$ProcessId)
Add-Type @"
using System;
using System.Runtime.InteropServices;
public static class FkConsole {
    [DllImport("kernel32.dll")] public static extern bool FreeConsole();
    [DllImport("kernel32.dll", SetLastError = true)] public static extern bool AttachConsole(uint processId);
    [DllImport("kernel32.dll")] public static extern bool SetConsoleCtrlHandler(IntPtr handler, bool add);
    [DllImport("kernel32.dll", SetLastError = true)] public static extern bool GenerateConsoleCtrlEvent(uint ctrlEvent, uint processGroupId);
}
"@
[FkConsole]::FreeConsole() | Out-Null
if (-not [FkConsole]::AttachConsole([uint32]$ProcessId)) { exit 2 }
[FkConsole]::SetConsoleCtrlHandler([IntPtr]::Zero, $true) | Out-Null  # this process ignores the Ctrl+C itself
$sent = [FkConsole]::GenerateConsoleCtrlEvent(0, 0)
Start-Sleep -Milliseconds 500
[FkConsole]::FreeConsole() | Out-Null
if ($sent) { exit 0 } else { exit 3 }
