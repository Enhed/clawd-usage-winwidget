#requires -version 5
<#
  Screenshots for the README: boots the widget modules in a temporary copy with
  fake data and renders the expanded window to PNG via RenderTargetBitmap.
    preview - the /usage stats, sessions and the Claude Code version;
    history - the 7-day chart (hovered) and made-up projects, the widget itself on top;
    claude  - the Claude Code tab of Settings over a made-up settings.json, its top
              and its bottom side by side.
  Run from Windows PowerShell (not Git Bash):

    .\tools\screenshot.ps1 preview                    # -> docs\preview.png
    .\tools\screenshot.ps1 history                    # -> docs\history.png
    .\tools\screenshot.ps1 claude                     # -> docs\claude-settings.png
    .\tools\screenshot.ps1 history -Out $env:TEMP\h.png -Lang ru
#>
param([Parameter(Mandatory)][ValidateSet('preview', 'history', 'claude')][string]$Kind,
      [string]$Out, [string]$Lang = 'en')
$repo = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
if (-not $Out) { $Out = Join-Path $repo "docs\$(if ($Kind -eq 'claude') { 'claude-settings' } else { $Kind }).png" }
$isHist = $Kind -eq 'history'

Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName System.Windows.Forms
Add-Type -Namespace Win32 -Name IconUtil -MemberDefinition @'
    [System.Runtime.InteropServices.DllImport("user32.dll", SetLastError = true)]
    public static extern bool DestroyIcon(System.IntPtr hIcon);
'@
$ErrorActionPreference = 'Stop'
$WidgetVersion = [regex]::Match((Get-Content (Join-Path $repo 'widget.ps1') -Raw), "WidgetVersion = '([^']+)'").Groups[1].Value

# A copy of its own: config.json and usage-history.json are written next to the modules.
$Root = Join-Path $env:TEMP "cuw-shot-$PID"
if (Test-Path $Root) { Remove-Item $Root -Recurse -Force }
New-Item -ItemType Directory $Root | Out-Null
Copy-Item (Join-Path $repo 'lib'), (Join-Path $repo 'skins') $Root -Recurse
Copy-Item (Join-Path $repo '*.xaml'), (Join-Path $repo '*.md') $Root
$script:Root       = $Root
$script:ConfigPath = Join-Path $Root 'config.json'
$script:IsAdmin    = $false

@{
    language = $Lang; scale = 1.0; expanded = $true; showAccount = $false; showStats = (-not $isHist)
    showSessions = $true; showStatus = $true; showHistory = $isHist; showMascot = $true; showSky = $true
    showAdvisor = $false; showChat = $false; showTasks = $false; clawdSession = $false
    topmost = $true; left = 40; top = 40; theme = 'default'; skin = 'default'
} | ConvertTo-Json | Out-File $script:ConfigPath -Encoding utf8

# Fake history: the widget sampling every 5 minutes, off at night; the 5-hour
# window fills while working and resets; the week grows and resets once.
$rnd   = New-Object System.Random 7
$now   = Get-Date
$start = $now.AddDays(-7)
$weekReset = $now.Date.AddDays(-3).AddHours(6)
$rows = New-Object System.Collections.ArrayList
$sess = 0.0; $week = 34.0; $winEnd = $null
$dayK = @{}
$t = $start
while ($t -le $now) {
    $h = $t.Hour
    $on = ($h -ge 9 -or $h -lt 1)
    if (-not $dayK.ContainsKey($t.Date)) { $dayK[$t.Date] = 0.45 + 0.9 * $rnd.NextDouble() }
    if ($t.DayOfWeek -eq 'Saturday') { $dayK[$t.Date] = 0.35 }
    if ($t -ge $weekReset -and $t.AddMinutes(-5) -lt $weekReset) { $week = 0.0 }
    if ($winEnd -and $t -ge $winEnd) { $sess = 0.0; $winEnd = $null }
    if ($on) {
        # Busy stretches in the afternoon and evening, quiet ones in between.
        $busy = ($h -ge 11 -and $h -lt 14) -or ($h -ge 16 -and $h -lt 19) -or ($h -ge 21 -and $h -lt 24)
        if ($busy -and $rnd.Next(5) -gt 0) {
            if (-not $winEnd) { $winEnd = $t.AddHours(5) }
            $d = $dayK[$t.Date] * (0.6 + 1.6 * $rnd.NextDouble())
            # 100.0, not 100: Min(int, double) would round to a whole percent and never grow.
            $sess = [math]::Min(100.0, $sess + $d)
            $week = [math]::Min(100.0, $week + $d * 0.1)
        }
        $m = [int][math]::Floor(([DateTimeOffset]$t).ToUnixTimeSeconds() / 60)
        [void]$rows.Add(('[{0},{1},{2}]' -f $m, [int]$sess, [int]$week))
    }
    $t = $t.AddMinutes(5)
}
# The Claude Code tab reads ~\.claude\settings.json: a made-up one, in a home of its own,
# so that the tab shows ~\.claude and not the temporary folder.
if ($Kind -eq 'claude') {
    $env:USERPROFILE = $Root
    Remove-Item Env:\CLAUDE_CONFIG_DIR -ErrorAction SilentlyContinue
    New-Item -ItemType Directory (Join-Path $Root '.claude') | Out-Null
    [System.IO.File]::WriteAllText((Join-Path $Root '.claude\settings.json'), (@'
{
  "model": "opus",
  "permissions": {
    "defaultMode": "acceptEdits"
  },
  "outputStyle": "Explanatory",
  "cleanupPeriodDays": 60,
  "theme": "dark",
  "tui": "fullscreen",
  "awaySummaryEnabled": false,
  "remoteControlAtStartup": true,
  "inputNeededNotifEnabled": true
}
'@).Replace("`r`n", "`n"))
}
[System.IO.File]::WriteAllText((Join-Path $Root 'usage-history.json'), '{"backfilled":true,"samples":[' + ($rows -join ',') + ']}')

foreach ($m in @(
    'config', 'i18n', 'usage', 'version', 'account', 'sessions', 'clawd-session', 'status', 'format', 'theme', 'window',
    'mascot', 'skins', 'hearts', 'mascot-step', 'weather', 'sky', 'scene', 'space', 'ocean', 'advisor', 'history','reminders', 'lists', 'chat', 'tasks', 'panel', 'panel-pages', 'remind-popup', 'settings', 'claude-settings', 'mascot-menu', 'tray',
    'update', 'tray-menu', 'events'
  )) {
    . (Join-Path $script:Root "lib\$m.ps1")
}

# No real probes: everything but the status line is made up.
function Start-UsageProbe { }
function Start-AuthProbe { }
function Start-VersionProbe { }
function Start-ReleaseProbe { }
function Start-WeatherProbe { }
function Start-AdvisorScan { }
function Start-ClawdSession { }
function Update-ClawdSession($ss) { }
function Start-HistoryJob([string]$kind) { }
function S([string]$name, [bool]$busy = $false) {
    return @{ name = $name; cwd = "C:\code\$name"; busy = $busy; waiting = $false }
}
if ($isHist) { $script:FakeSessions = @((S 'clawd-usage-winwidget'), (S 'pixel-garden')) }
else         { $script:FakeSessions = @((S 'clawd-usage-winwidget' $true), (S 'pixel-garden'), (S 'invoice-bot'), (S 'dotfiles')) }
function Get-Sessions { return ,@($script:FakeSessions) }
$script:Usage = @{
    session = [int]$sess; week = [int]$week; fable = 12
    sessionReset = $now.AddMinutes(137); weekReset = $weekReset.AddDays(7); fableReset = $weekReset.AddDays(7)
    day = $null; week7 = $null
}
if (-not $isHist) {
    # The stats as /usage prints them; the widget shortens and translates them itself.
    $script:Usage.session = 37; $script:Usage.week = 23; $script:Usage.fable = 19
    $script:Usage.sessionReset = $now.AddMinutes(164)
    $script:Usage.day = @{ requests = 412; sessions = 9; lines = @(
        '46% of your usage was at >150k context',
        '27% of your usage went to always-on context over 40k',
        '12% of your usage came from subagent-heavy sessions',
        'Top skills: /dataviz 5%',
        'Top MCP servers: claude-in-chrome 3%') }
    $script:Usage.week7 = @{ requests = 2861; sessions = 54; lines = @(
        '71% of your usage was at >150k context',
        '52% of your usage came from subagent-heavy sessions',
        '44% of your usage came from sessions active for 8+ hours',
        'Top subagents: general-purpose 4%, Explore 2%',
        'Top MCP servers: claude-in-chrome 6%') }
    $script:VerLocal = '2.1.310'; $script:VerLatest = '2.1.310'
}
$script:UsageAt = Get-Date
if ($isHist) { $script:Sky.force = 'day'; $script:Sky.forceWx = 1 }
else         { $script:Sky.force = 'night'; $script:Sky.forceWx = 0 }
$script:Sky.key = ''

# Projects: weights per hour, the widget itself on top.
$names = @(@('clawd-usage-winwidget', 38), @('pixel-garden', 22), @('invoice-bot', 17), @('tide-tables', 11), @('dotfiles', 6), @('~', 4))
$proj = @{ total = @{}; hours = @{}; paths = @{} }
foreach ($n in $names) { $proj.paths[$n[0]] = $(if ($n[0] -eq '~') { $env:USERPROFILE } else { "C:\code\$($n[0])" }) }
$h0 = [int][math]::Floor(([DateTimeOffset]$start).ToUnixTimeSeconds() / 3600)
$h1 = [int][math]::Floor(([DateTimeOffset]$now).ToUnixTimeSeconds() / 3600)
for ($h = $h0; $h -le $h1; $h++) {
    $proj.hours[$h] = @{}
    foreach ($n in $names) {
        $w = $n[1] * $rnd.NextDouble()
        $proj.hours[$h][$n[0]] = $w
        $proj.total[$n[0]] = [double]$proj.total[$n[0]] + $w
    }
}
# The hover point: yesterday evening, in the middle of work on the widget.
$hoverT = $now.Date.AddDays(-1).AddHours(18).AddMinutes(40)
$proj.hours[[int][math]::Floor(([DateTimeOffset]$hoverT).ToUnixTimeSeconds() / 3600)]['clawd-usage-winwidget'] = 500
$hoverAt = ($hoverT - $start).TotalMinutes / ($now - $start).TotalMinutes
$script:Proj = $proj; $script:ProjAt = Get-Date; $script:ProjTry = Get-Date

$UI.MascotTag.Visibility = 'Collapsed'
$win.Show()
Update-Texts
Set-Details $true
Update-Widget

$k  = 2.0

function Get-Frame($w) {
    $w.UpdateLayout()
    $bw = [int][math]::Ceiling($w.ActualWidth * $k); $bh = [int][math]::Ceiling($w.ActualHeight * $k)
    $rtb = New-Object System.Windows.Media.Imaging.RenderTargetBitmap $bw, $bh, (96 * $k), (96 * $k), ([System.Windows.Media.PixelFormats]::Pbgra32)
    $rtb.Render($w)
    return $rtb
}

function Save-Png($bmp) {
    $enc = New-Object System.Windows.Media.Imaging.PngBitmapEncoder
    $enc.Frames.Add([System.Windows.Media.Imaging.BitmapFrame]::Create($bmp))
    $fs = [System.IO.File]::Create($Out); $enc.Save($fs); $fs.Close()
}

# Two frames of the settings window - the tab from the top and scrolled to the end -
# side by side on the README's dark background, as in docs\settings.png.
if ($Kind -eq 'claude') {
    [void](Show-Settings)
    Set-SettingsTab 'claude'
    # Cut at the Terminal header: the first frame up to it, the second from it on.
    $setWin.UpdateLayout()
    $head = (T 'cc.hTerminal').ToUpper()
    $cut = @($UI.SetPage.Children | Where-Object { $_ -is [System.Windows.Controls.TextBlock] -and $_.Text -eq $head })[0]
    $y = $cut.TranslatePoint((New-Object System.Windows.Point 0, 0), $UI.SetPage).Y - $cut.Margin.Top
    $all = $UI.SetPage.ActualHeight
    $UI.SetScroll.MaxHeight = $y
    $top = Get-Frame $setWin
    $UI.SetScroll.MaxHeight = $all - $y
    $setWin.UpdateLayout()
    $UI.SetScroll.ScrollToVerticalOffset($y)
    $end = Get-Frame $setWin
    $gap = 16 * $k
    $W = $top.PixelWidth + $gap + $end.PixelWidth; $H = [math]::Max($top.PixelHeight, $end.PixelHeight)
    $dv = New-Object System.Windows.Media.DrawingVisual
    $dc = $dv.RenderOpen()
    $dc.DrawRectangle((New-Brush '#FF0D1117'), $null, (New-Object System.Windows.Rect 0, 0, ($W / $k), ($H / $k)))
    $dc.DrawImage($top, (New-Object System.Windows.Rect 0, 0, ($top.PixelWidth / $k), ($top.PixelHeight / $k)))
    $dc.DrawImage($end, (New-Object System.Windows.Rect (($top.PixelWidth + $gap) / $k), 0, ($end.PixelWidth / $k), ($end.PixelHeight / $k)))
    $dc.Close()
    $rtb = New-Object System.Windows.Media.Imaging.RenderTargetBitmap $W, $H, (96 * $k), (96 * $k), ([System.Windows.Media.PixelFormats]::Pbgra32)
    $rtb.Render($dv)
    Save-Png $rtb
    Stop-Widget
    Remove-Item $Root -Recurse -Force -ErrorAction SilentlyContinue
    return
}
$sw = [Diagnostics.Stopwatch]::StartNew()
$shot = New-Object System.Windows.Threading.DispatcherTimer
$shot.Interval = [TimeSpan]::FromMilliseconds(250)
# A few seconds for the sky and the status line, then one frame.
$shot.add_Tick({
    if ($sw.Elapsed.TotalSeconds -lt 3) { return }
    if (-not $script:Status -and $sw.Elapsed.TotalSeconds -lt 8) { return }
    $shot.Stop()
    Update-Widget
    $win.UpdateLayout()
    if ($isHist) { Show-HistPoint ($BarWidth * $hoverAt) }
    Save-Png (Get-Frame $win)
    Stop-Widget
})
$shot.Start()
[System.Windows.Threading.Dispatcher]::Run()
Remove-Item $Root -Recurse -Force -ErrorAction SilentlyContinue
