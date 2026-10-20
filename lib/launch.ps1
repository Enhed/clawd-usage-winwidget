# ---------------------------------------------------------------- launch ----
# Background jobs (action commands, recurring tasks) are started here. An elevated
# widget passes its rights on to whatever it starts; with jobsNoAdmin they run with
# the user's usual rights instead - under the token of the desktop shell (Explorer),
# taken by an elevated process through CreateProcessWithTokenW.

$script:LaunchType = $false

function Test-JobsNoAdmin { return ($script:IsAdmin -and [bool]$script:Cfg.jobsNoAdmin) }

# Compiled on first use: most widgets are never elevated.
function Initialize-Launch {
    if ($script:LaunchType) { return }
    Add-Type -TypeDefinition @'
using System;
using System.Diagnostics;
using System.Runtime.InteropServices;
using System.Text;

public static class CuwUnelevated {
    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    struct STARTUPINFO {
        public int cb; public string lpReserved, lpDesktop, lpTitle;
        public int dwX, dwY, dwXSize, dwYSize, dwXCountChars, dwYCountChars, dwFillAttribute, dwFlags;
        public short wShowWindow, cbReserved2;
        public IntPtr lpReserved2, hStdInput, hStdOutput, hStdError;
    }
    struct PROCESS_INFORMATION { public IntPtr hProcess, hThread; public int dwProcessId, dwThreadId; }

    [DllImport("user32.dll")] static extern IntPtr GetShellWindow();
    [DllImport("user32.dll")] static extern int GetWindowThreadProcessId(IntPtr hWnd, out int pid);
    [DllImport("kernel32.dll", SetLastError = true)] static extern IntPtr OpenProcess(int access, bool inherit, int pid);
    [DllImport("kernel32.dll")] static extern bool CloseHandle(IntPtr h);
    [DllImport("kernel32.dll")] static extern int ResumeThread(IntPtr h);
    [DllImport("kernel32.dll")] static extern bool TerminateProcess(IntPtr h, int code);
    [DllImport("advapi32.dll", SetLastError = true)] static extern bool OpenProcessToken(IntPtr h, int access, out IntPtr token);
    [DllImport("advapi32.dll", SetLastError = true)]
    static extern bool DuplicateTokenEx(IntPtr token, int access, IntPtr attrs, int level, int type, out IntPtr dup);
    [DllImport("advapi32.dll", SetLastError = true)]
    static extern bool GetTokenInformation(IntPtr token, int cls, out int value, int size, out int len);
    [DllImport("advapi32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
    static extern bool CreateProcessWithTokenW(IntPtr token, int logonFlags, string app, StringBuilder cmd, int flags,
                                               IntPtr env, string dir, ref STARTUPINFO si, out PROCESS_INFORMATION pi);

    static Exception Fail(string what) {
        return new Exception(what + ": " + new System.ComponentModel.Win32Exception(Marshal.GetLastWin32Error()).Message);
    }

    // Started suspended, so the Process object holds a handle before it can end
    // (its exit code stays readable), then let go. Hidden console window.
    public static Process Start(string cmdLine, string dir) {
        int pid;
        GetWindowThreadProcessId(GetShellWindow(), out pid);
        if (pid == 0) throw new Exception("no desktop shell to take the user's rights from");
        IntPtr proc = IntPtr.Zero, token = IntPtr.Zero, dup = IntPtr.Zero;
        try {
            proc = OpenProcess(0x1000, false, pid);                     // PROCESS_QUERY_LIMITED_INFORMATION
            if (proc == IntPtr.Zero) throw Fail("OpenProcess");
            if (!OpenProcessToken(proc, 0x000B, out token)) throw Fail("OpenProcessToken");
            int elevated, len;
            if (GetTokenInformation(token, 20, out elevated, 4, out len) && elevated != 0)
                throw new Exception("the desktop shell itself runs elevated");
            if (!DuplicateTokenEx(token, 0x02000000, IntPtr.Zero, 2, 1, out dup)) throw Fail("DuplicateTokenEx");
            STARTUPINFO si = new STARTUPINFO();
            si.cb = Marshal.SizeOf(si);
            si.dwFlags = 1;                                             // STARTF_USESHOWWINDOW, SW_HIDE
            PROCESS_INFORMATION pi;
            // CREATE_SUSPENDED | CREATE_NEW_CONSOLE
            if (!CreateProcessWithTokenW(dup, 0, null, new StringBuilder(cmdLine), 0x14, IntPtr.Zero, dir, ref si, out pi))
                throw Fail("CreateProcessWithTokenW");
            try {
                Process p = Process.GetProcessById(pi.dwProcessId);
                IntPtr keep = p.Handle;
                ResumeThread(pi.hThread);
                return p;
            } catch {
                TerminateProcess(pi.hProcess, 1);
                throw;
            } finally {
                CloseHandle(pi.hThread);
                CloseHandle(pi.hProcess);
            }
        } finally {
            if (dup != IntPtr.Zero) CloseHandle(dup);
            if (token != IntPtr.Zero) CloseHandle(token);
            if (proc != IntPtr.Zero) CloseHandle(proc);
        }
    }
}
'@
    $script:LaunchType = $true
}

# Start-Process with redirected streams and a hidden window, as the jobs always did;
# $argv is joined with spaces, the same as Start-Process does. Elevated with
# jobsNoAdmin, a small PowerShell with the user's rights starts it instead and waits,
# passing its exit code on; taskkill /T on it still takes the whole tree.
function Start-JobProcess([string]$exe, [string[]]$argv, [string]$dir, [string]$in, [string]$out, [string]$err) {
    $splat = @{ FilePath = $exe; WorkingDirectory = $dir; RedirectStandardOutput = $out; RedirectStandardError = $err
                WindowStyle = 'Hidden'; PassThru = $true }
    if ($argv) { $splat.ArgumentList = $argv }
    if ($in) { $splat.RedirectStandardInput = $in }
    if (-not (Test-JobsNoAdmin)) {
        $p = Start-Process @splat
        [void]$p.Handle
        return $p
    }
    $q = { param($s) "'" + ([string]$s).Replace("'", "''") + "'" }
    $parts = foreach ($k in $splat.Keys) {
        if ($k -eq 'PassThru') { '-PassThru' }
        elseif ($k -eq 'ArgumentList') { "-ArgumentList $(($argv | ForEach-Object { & $q $_ }) -join ',')" }
        else { "-$k $(& $q $splat[$k])" }
    }
    # Not -Wait: it waits for every child too, and a program the job opens may stay.
    # In a file that removes itself, not -EncodedCommand: CreateProcessWithTokenW
    # takes at most 1024 characters of command line.
    $code = "Remove-Item -LiteralPath `$PSCommandPath -Force -ErrorAction SilentlyContinue`r`n" +
            "try { `$p = Start-Process $($parts -join ' ') -ErrorAction Stop; [void]`$p.Handle; `$p.WaitForExit(); exit `$p.ExitCode }`r`n" +
            "catch { [System.IO.File]::WriteAllText($(& $q $err), `$_.Exception.Message); exit 1 }"
    $run = "$err.run.ps1"
    [System.IO.File]::WriteAllText($run, $code, (New-Object System.Text.UTF8Encoding $true))
    Initialize-Launch
    $ps = Join-Path $PSHOME 'powershell.exe'
    try { return [CuwUnelevated]::Start("`"$ps`" -NoProfile -NonInteractive -ExecutionPolicy Bypass -File `"$run`"", $dir) }
    catch { Remove-Item -LiteralPath $run -Force -ErrorAction SilentlyContinue; throw }
}
