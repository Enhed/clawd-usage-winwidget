#requires -version 5
<#
  clawd-usage-winwidget - a floating window + tray icon showing current Claude usage.
  All data is official: limit percentages and stats come from `claude -p /usage`,
  the latest version number from downloads.claude.ai. No third-party dependencies.
  The only third-party bit is weather for the sky behind the mascot (Open-Meteo or met.no,
  location by IP via ipwho.is); disabled with the showSky key.
#>

Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName System.Windows.Forms

Add-Type -Namespace Win32 -Name IconUtil -MemberDefinition @'
    [System.Runtime.InteropServices.DllImport("user32.dll", SetLastError = true)]
    public static extern bool DestroyIcon(System.IntPtr hIcon);
'@

# The widget's own version; what changed in each one - CHANGELOG.md.
$WidgetVersion = '1.5.3'

$script:Root       = Split-Path -Parent $MyInvocation.MyCommand.Path
$script:ConfigPath = Join-Path $script:Root 'config.json'
$script:IsAdmin    = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
                         [Security.Principal.WindowsBuiltInRole]::Administrator)

# runAsAdmin: start over elevated, through the usual UAC prompt. Declined - the
# widget just runs without elevation.
$wantAdmin = $false
try { $wantAdmin = [bool](([System.IO.File]::ReadAllText($script:ConfigPath) | ConvertFrom-Json).runAsAdmin) } catch {}
if ($wantAdmin -and -not $script:IsAdmin) {
    try {
        Start-Process powershell.exe -Verb RunAs -WindowStyle Hidden -ErrorAction Stop `
            -ArgumentList '-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass', '-File', "`"$($MyInvocation.MyCommand.Path)`""
        exit 0
    } catch {}
}

$ErrorActionPreference = 'Stop'
# The widget has no console: a question from PowerShell ("delete the folder with
# everything in it?") would wait forever unseen. Never ask - and with -NonInteractive
# in start-widget.vbs a question that slips through is an error, not a hang.
$ConfirmPreference = 'None'

# An error while starting up (a module failing to load...) would end the hidden
# process without a trace - write it down first.
trap {
    try {
        "$(Get-Date -Format s)`tstart: $($_.Exception.Message)`t$($_.InvocationInfo.PositionMessage)" |
            Out-File (Join-Path $script:Root 'widget-error.log') -Append -Encoding utf8
    } catch {}
    exit 1
}

# One instance per user - otherwise autostart plus a manual start would give two icons.
# The mutex of an elevated copy is closed to a normal one - that also means "already running".
$isNew = $false
try {
    # tools/smoke.ps1 starts a test copy next to the running widget - under a mutex of its own.
    $mutexName = 'Local\clawd-usage-winwidget' + $(if ($env:CUW_SMOKE) { '-smoke' } else { '' })
    $script:Mutex = New-Object System.Threading.Mutex($true, $mutexName, [ref]$isNew)
} catch { exit 0 }
if (-not $isNew) { exit 0 }

# Probe outputs are named by PID (cuw-usage-<pid>.txt and so on): those of earlier
# runs are of no use to anyone - only one copy runs at a time. -Recurse: an
# unpacked update is a folder, and without it Remove-Item asks about its contents -
# in a hidden window that question waits forever.
Remove-Item (Join-Path $env:TEMP 'cuw-*') -Recurse -Force -Confirm:$false -ErrorAction SilentlyContinue

# Modules are dot-sourced into the shared script scope: order matters, each one
# relies on the variables and functions of the previous ones.
foreach ($m in @(
    'config', 'i18n', 'usage', 'version', 'account', 'sessions', 'clawd-session', 'status', 'format', 'window',
    'mascot', 'hearts', 'mascot-step', 'weather', 'sky', 'advisor', 'reminders', 'lists', 'chat', 'tasks', 'panel', 'panel-pages', 'remind-popup', 'mascot-menu', 'tray',
    'update', 'tray-menu', 'events'
  )) {
    . (Join-Path $script:Root "lib\$m.ps1")
}

Update-Texts
if ($script:Cfg.expanded) { Set-Details $true }

# An error in a click handler must not take the whole widget down: log it and go on.
[System.Windows.Threading.Dispatcher]::CurrentDispatcher.add_UnhandledException({
    param($s, $e)
    $e.Handled = $true
    try {
        "$(Get-Date -Format s)`tui: $($e.Exception.Message)" |
            Out-File (Join-Path $script:Root 'widget-error.log') -Append -Encoding utf8
    } catch {}
})

$win.Show()
Update-Widget
# Got as far as the window and the first update: tools/smoke.ps1 waits for this file.
if ($env:CUW_READY_FILE) { try { [System.IO.File]::WriteAllText($env:CUW_READY_FILE, "$WidgetVersion $PID") } catch {} }
$kick.Start()
[System.Windows.Threading.Dispatcher]::Run()
