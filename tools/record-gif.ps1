#requires -version 5
<#
  GIF recorder for the README: boots the widget modules with fake data and a
  scripted scenario, renders the window to PNG frames via RenderTargetBitmap.
  Run from Windows PowerShell (not Git Bash), then tools/compose-gif.py:

    .\tools\record-gif.ps1 -Scenario sleep -Out $env:TEMP\gif\sleep
    python tools/compose-gif.py $env:TEMP\gif\sleep docs/sleep.gif

  Scenarios: tour, sleep, limit, reset, hearts, weather, clicks.
#>
param([Parameter(Mandatory)][string]$Scenario, [Parameter(Mandatory)][string]$Out,
      [string]$Root)
# $PSScriptRoot is empty in parameter defaults in PowerShell 5.1.
if (-not $Root) { $Root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path) }

Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName System.Windows.Forms
Add-Type -Namespace Win32 -Name IconUtil -MemberDefinition @'
    [System.Runtime.InteropServices.DllImport("user32.dll", SetLastError = true)]
    public static extern bool DestroyIcon(System.IntPtr hIcon);
'@
$ErrorActionPreference = 'Stop'

$script:Root       = $Root
$script:ConfigPath = Join-Path $Out 'config.json'
New-Item -ItemType Directory -Force $Out | Out-Null
Get-ChildItem $Out -Filter 'f*.png' | Remove-Item
@{
    language = 'en'; scale = 1.0; showAccount = $false; showStats = $false; expanded = $false
    showSessions = $true; showStatus = $true; topmost = $true; left = 40; top = 40
} | ConvertTo-Json | Out-File $script:ConfigPath -Encoding utf8

foreach ($m in @(
    'config', 'i18n', 'usage', 'version', 'account', 'sessions', 'status', 'format', 'window',
    'mascot', 'hearts', 'mascot-step', 'weather', 'sky', 'mascot-menu', 'tray',
    'update', 'tray-menu', 'events'
  )) {
    . (Join-Path $script:Root "lib\$m.ps1")
}

# Fake data instead of probes.
function Start-UsageProbe { }
function Start-AuthProbe { }
$script:FakeSessions = @()
function Get-Sessions { return ,@($script:FakeSessions) }

function S([string]$name, [string]$state = 'idle', [string]$for = '') {
    return @{ name = $name; cwd = "C:\code\$name"; busy = ($state -eq 'busy')
              waiting = ($state -eq 'wait'); waitingFor = $for }
}
function Set-Usage([int]$pct, [double]$resetMin = 192) {
    $script:Usage = @{
        session = $pct; week = 41; fable = 18
        sessionReset = (Get-Date).AddMinutes($resetMin)
        weekReset = (Get-Date).AddDays(2.4); fableReset = (Get-Date).AddDays(2.4)
        day = $null; week7 = $null
    }
    $script:UsageAt = Get-Date
}
function Set-Sky([string]$phase, $code) {
    $script:Sky.force = $phase; $script:Sky.forceWx = $code; $script:Sky.key = ''
}
function Click { $script:Mz.idleSince = Get-Date; Start-MascotClick }

# Scenario: list of @(seconds, { action }); the last entry's time is the length.
$crop = $true
switch ($Scenario) {
    'tour' {
        $crop = $false
        $steps = @(
            @(0,    { Set-Sky 'day' 2; Set-Usage 34; $script:FakeSessions = @((S 'api'), (S 'web')) }),
            @(2.5,  { $script:FakeSessions = @((S 'api' 'busy'), (S 'web')) }),
            @(4,    { Set-Usage 36 }), @(5.5, { Set-Usage 39 }), @(7, { Set-Usage 42 }),
            @(8.5,  { $script:FakeSessions = @((S 'api'), (S 'web')) }),
            @(10.5, { $script:FakeSessions = @((S 'api'), (S 'web' 'wait' 'permission')) }),
            @(14.5, { })
        )
    }
    'sleep' {
        $steps = @(
            @(0,   { Set-Sky 'night' 0; Set-Usage 12; $script:FakeSessions = @((S 'api')) }),
            @(1.5, { $script:FakeSessions = @() }),
            @(9,   { })
        )
    }
    'limit' {
        $steps = @(
            @(0,   { Set-Sky 'day' 3; Set-Usage 100; $script:FakeSessions = @((S 'api')) }),
            @(2,   { Click }),
            @(9.5, { })
        )
    }
    'reset' {
        $steps = @(
            @(0,   { Set-Sky 'day' 1; Set-Usage 96 3; $script:FakeSessions = @((S 'api' 'busy')) }),
            @(4,   { Set-Usage 0 300 }),
            @(8.5, { })
        )
    }
    'hearts' {
        $steps = @(
            @(0,  { Set-Sky 'dusk' 2; Set-Usage 10; $script:FakeSessions = @((S 'api' 'busy')); $script:Mz.drainT = 0 }),
            @(15.5, { })
        )
    }
    'weather' {
        $steps = @(
            @(0,  { Set-Sky 'day' 63; Set-Usage 27; $script:FakeSessions = @((S 'api')) }),
            @(3,  { Set-Sky 'night' 73 }),
            @(6,  { Set-Sky 'dusk' 95 }),
            @(9,  { Set-Sky 'dawn' 2 }),
            @(12, { })
        )
    }
    'clicks' {
        $steps = @(
            @(0,   { Set-Sky 'day' 1; Set-Usage 22; $script:FakeSessions = @((S 'api')) }),
            @(1,   { Click }), @(3.5, { Click }), @(6, { Click }), @(8.5, { Click }),
            @(11,  { })
        )
    }
    default { throw "unknown scenario $Scenario" }
}

$UI.MascotTag.Visibility = 'Collapsed'
$UI.LineAccount.Visibility = 'Collapsed'
$win.Show()
Update-Texts

$k     = 2.0
$sw    = [Diagnostics.Stopwatch]::StartNew()
$state = @{ i = 0; n = 0 }
$frames = New-Object System.Collections.Generic.List[object]
# Capture right after every mascot step: one frame per animation step, so the
# GIF plays at the native 90 ms pace even if rendering slows the wall clock.
$mascotTimer.add_Tick({
    if ($state.done) { return }
    # Warm-up: wait for the status line so the first frames aren't "loading...".
    if (-not $state.ready) {
        if (-not $script:Status -and $sw.Elapsed.TotalSeconds -lt 8) { return }
        $state.ready = $true
    }
    $t = $state.n * 0.09
    $changed = $false
    while ($state.i -lt $steps.Count -and $steps[$state.i][0] -le $t) {
        & $steps[$state.i][1]
        $state.i++
        $changed = $true
    }
    if ($changed) { Update-Widget }
    if ($state.i -ge $steps.Count) {
        $state.done = $true
        $cy = $null
        if ($crop) {
            $p  = $UI.LineReset.TranslatePoint((New-Object System.Windows.Point 0, $UI.LineReset.ActualHeight), $win)
            $cy = [int][math]::Ceiling(($p.Y + 9) * $k)
        }
        @{ fps = 1 / 0.09; cropH = $cy } | ConvertTo-Json | Out-File (Join-Path $Out 'meta.json') -Encoding ascii
        for ($j = 0; $j -lt $frames.Count; $j++) {
            $enc = New-Object System.Windows.Media.Imaging.PngBitmapEncoder
            $enc.Frames.Add([System.Windows.Media.Imaging.BitmapFrame]::Create($frames[$j]))
            $fs = [System.IO.File]::Create((Join-Path $Out ('f{0:0000}.png' -f $j)))
            $enc.Save($fs); $fs.Close()
        }
        Stop-Widget
        return
    }
    $w = [int][math]::Ceiling($win.ActualWidth * $k); $h = [int][math]::Ceiling($win.ActualHeight * $k)
    $rtb = New-Object System.Windows.Media.Imaging.RenderTargetBitmap $w, $h, (96 * $k), (96 * $k), ([System.Windows.Media.PixelFormats]::Pbgra32)
    $rtb.Render($win)
    $rtb.Freeze()
    $frames.Add($rtb)
    $state.n++
})
[System.Windows.Threading.Dispatcher]::Run()
