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

$ErrorActionPreference = 'Stop'

# One instance per user - otherwise autostart plus a manual start would give two icons.
$isNew = $false
$script:Mutex = New-Object System.Threading.Mutex($true, 'Local\clawd-usage-winwidget', [ref]$isNew)
if (-not $isNew) { exit 0 }

$script:Root       = Split-Path -Parent $MyInvocation.MyCommand.Path
$script:ConfigPath = Join-Path $script:Root 'config.json'

# Modules are dot-sourced into the shared script scope: order matters, each one
# relies on the variables and functions of the previous ones.
foreach ($m in @(
    'config', 'i18n', 'usage', 'version', 'account', 'sessions', 'status', 'format', 'window',
    'mascot', 'hearts', 'mascot-step', 'weather', 'sky', 'mascot-menu', 'tray',
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
