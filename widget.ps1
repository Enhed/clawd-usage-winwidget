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
$WidgetVersion = '1.1.0'

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
            -ArgumentList '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$($MyInvocation.MyCommand.Path)`""
        exit 0
    } catch {}
}

$ErrorActionPreference = 'Stop'

# One instance per user - otherwise autostart plus a manual start would give two icons.
# The mutex of an elevated copy is closed to a normal one - that also means "already running".
$isNew = $false
try {
    $script:Mutex = New-Object System.Threading.Mutex($true, 'Local\clawd-usage-winwidget', [ref]$isNew)
} catch { exit 0 }
if (-not $isNew) { exit 0 }

# Probe outputs are named by PID (cuw-usage-<pid>.txt and so on): those of earlier
# runs are of no use to anyone - only one copy runs at a time.
Remove-Item (Join-Path $env:TEMP 'cuw-*') -Force -ErrorAction SilentlyContinue

# Modules are dot-sourced into the shared script scope: order matters, each one
# relies on the variables and functions of the previous ones.
foreach ($m in @(
    'config', 'i18n', 'usage', 'version', 'account', 'sessions', 'clawd-session', 'status', 'format', 'window',
    'mascot', 'hearts', 'mascot-step', 'weather', 'sky', 'advisor', 'reminders', 'chat', 'panel', 'mascot-menu', 'tray',
    'update', 'tray-menu', 'events'
  )) {
    . (Join-Path $script:Root "lib\$m.ps1")
}

Update-Texts
if ($script:Cfg.expanded) { Set-Details $true }

$win.Show()
Update-Widget
$kick.Start()
[System.Windows.Threading.Dispatcher]::Run()
