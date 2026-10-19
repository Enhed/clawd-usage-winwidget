# --------------------------------------------------------------- actions ----
# One-time actions: something to do once, now or at a set time. Plain files in
# Clawd's home, like reminders and tasks:
#   actions\2026-10-19 23-00 Backup.md
#   ---
#   at: 2026-10-19T23:00
#   kind: command           (or clawd)
#   ---
#   C:\Tools\backup.cmd
# `command` - the widget runs it itself, no Claude: a program, a file or a folder is
# opened, anything else is a PowerShell script; its exit code and output are kept.
# `clawd` - the words go to the chat when due, and Clawd does it the chat's way
# (his `run` script waits for a click unless auto-run is on).
# One due while the widget was off is not run late (a "shut down at 23:00" next
# morning would do harm): it is kept in the history as missed.

$ActionsStatePath = Join-Path $script:Root 'actions-state.json'
$ActionKinds      = @('clawd', 'command')
$ActionKeep       = 20       # history lines kept
$ActionLate       = 10       # minutes a missed one may still run after the start

$script:ActStart = Get-Date
$script:ActRuns  = New-Object System.Collections.ArrayList   # @{ proc; out; err; ps1; at; act }
$script:ActSeq   = 0

function Get-ActionsDir { return Join-Path (Get-ClawdHome) 'actions' }

# Planned actions, soonest first: @{ path; at; kind; text }.
function Get-Actions {
    $list = @()
    $dir = Get-ActionsDir
    if (-not [System.IO.Directory]::Exists($dir)) { return ,$list }
    foreach ($f in @(Get-ChildItem $dir -File -Filter *.md -ErrorAction SilentlyContinue)) {
        try { $raw = [System.IO.File]::ReadAllText($f.FullName, [System.Text.Encoding]::UTF8) } catch { continue }
        $a = @{ path = $f.FullName; at = $null; kind = 'clawd'; text = $raw.Trim() }
        $m = [regex]::Match($raw, '(?s)^\s*---\s*\r?\n(.*?)\r?\n---\s*\r?\n?(.*)$')
        if ($m.Success) {
            $a.text = $m.Groups[2].Value.Trim()
            $at = [regex]::Match($m.Groups[1].Value, '(?m)^\s*at:\s*(\S+)')
            if ($at.Success) { try { $a.at = [datetime]::Parse($at.Groups[1].Value, [System.Globalization.CultureInfo]::InvariantCulture) } catch {} }
            $k = [regex]::Match($m.Groups[1].Value, '(?m)^\s*kind:\s*(\w+)')
            if ($k.Success -and $ActionKinds -contains $k.Groups[1].Value.ToLower()) { $a.kind = $k.Groups[1].Value.ToLower() }
        }
        # No time - as soon as it is seen.
        if (-not $a.at) { $a.at = $f.CreationTime }
        if (-not $a.text) { continue }
        $list += $a
    }
    $list = @($list | Sort-Object { $_.at })
    return ,$list
}

function New-ActionFile([datetime]$at, [string]$kind, [string]$text) {
    $dir = Get-ActionsDir
    [void][System.IO.Directory]::CreateDirectory($dir)
    $title = ($text -replace '[\\/:*?"<>|\r\n]', ' ' -replace '\s+', ' ').Trim()
    if ($title.Length -gt 40) { $title = $title.Substring(0, 40).Trim() }
    $base = "$($at.ToString('yyyy-MM-dd HH-mm')) $title"
    $path = Join-Path $dir "$base.md"
    $i = 2
    while (Test-Path -LiteralPath $path) { $path = Join-Path $dir "$base ($i).md"; $i++ }
    $body = "---`nat: $($at.ToString('yyyy-MM-ddTHH:mm'))`nkind: $kind`n---`n$($text.Trim())`n"
    [System.IO.File]::WriteAllText($path, $body, (New-Object System.Text.UTF8Encoding $false))
    return $path
}

# History, newest last: @{ at; due; kind; text; state = done|failed|sent|missed|stopped; code; output }.
function Load-ActionHistory {
    $list = @()
    $raw = Load-JsonFile $ActionsStatePath
    foreach ($h in @($(if ($raw) { $raw.history }))) {
        if (-not $h) { continue }
        try {
            $list += @{ at = [datetime]$h.at; due = $(if ($h.due) { [datetime]$h.due } else { [datetime]$h.at })
                        kind = [string]$h.kind; text = [string]$h.text; state = [string]$h.state
                        code = $h.code; output = [string]$h.output }
        } catch {}
    }
    return ,$list
}

function Add-ActionHistory($a, [string]$state, $code = $null, [string]$output = '') {
    # Not @(Load-ActionHistory): it hands the list over as one object.
    $list = Load-ActionHistory
    $list += @{ at = Get-Date; due = $a.at; kind = $a.kind; text = $a.text; state = $state; code = $code; output = $output }
    $list = @($list | Select-Object -Last $ActionKeep)
    Save-JsonFile $ActionsStatePath @{ history = @($list | ForEach-Object {
        @{ at = $_.at.ToString('s'); due = $_.due.ToString('s'); kind = $_.kind; text = $_.text
           state = $_.state; code = $_.code; output = $_.output } }) }
}

# A path to something that exists, or a web address - opened, not run as a script.
function Get-ActionTarget([string]$text) {
    $t = $text.Trim()
    if ($t -match '[\r\n]') { return $null }
    $t = $t.Trim('"')
    if ($t -match '^(https?|mailto):') { return $t }
    try { if ([System.IO.Path]::IsPathRooted($t) -and (Test-Path -LiteralPath $t)) { return $t } } catch {}
    return $null
}

function Start-ActionRun($a) {
    try {
        $script:ActSeq++
        $ps1 = Join-Path $env:TEMP "cuw-act-$PID-$($script:ActSeq).ps1"
        $out = Join-Path $env:TEMP "cuw-act-out-$PID-$($script:ActSeq).txt"
        $err = Join-Path $env:TEMP "cuw-act-err-$PID-$($script:ActSeq).txt"
        $target = Get-ActionTarget $a.text
        $code = $(if ($target) { "Start-Process -FilePath '$($target.Replace("'", "''"))'" } else { $a.text })
        # With BOM and UTF-8 output, as the chat's scripts (Start-ChatRun).
        $body = "[Console]::OutputEncoding = [System.Text.Encoding]::UTF8`r`n" + $code
        [System.IO.File]::WriteAllText($ps1, $body, (New-Object System.Text.UTF8Encoding $true))
        # The file goes first: the run must not start twice.
        Remove-Item -LiteralPath $a.path -Force
        $p = Start-Process -FilePath (Join-Path $PSHOME 'powershell.exe') -WorkingDirectory $env:USERPROFILE `
                 -ArgumentList '-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass', '-File', "`"$ps1`"" `
                 -RedirectStandardOutput $out -RedirectStandardError $err -WindowStyle Hidden -PassThru
        [void]$p.Handle
        [void]$script:ActRuns.Add(@{ proc = $p; out = $out; err = $err; ps1 = $ps1; at = Get-Date; act = $a })
        $actTimer.Start()
    } catch {
        try { Remove-Item -LiteralPath $a.path -Force -ErrorAction SilentlyContinue } catch {}
        Add-ActionHistory $a 'failed' $null $_.Exception.Message
    }
}

function Stop-ActionRun($run) {
    try { & taskkill.exe /PID $run.proc.Id /T /F 2>&1 | Out-Null } catch {}
    $run.stopped = $true
}

function Collect-ActionRuns {
    foreach ($r in @($script:ActRuns)) {
        if (-not $r.proc.HasExited) { continue }
        $script:ActRuns.Remove($r)
        $code = $r.proc.ExitCode
        $text = ''
        foreach ($f in @($r.out, $r.err)) { try { $text += [System.IO.File]::ReadAllText($f, [System.Text.Encoding]::UTF8) } catch {} }
        $text = $text.Trim()
        if ($text.Length -gt 3000) { $text = '…' + $text.Substring($text.Length - 3000) }
        foreach ($f in @($r.out, $r.err, $r.ps1)) { try { Remove-Item -LiteralPath $f -Force -ErrorAction SilentlyContinue } catch {} }
        $state = $(if ($r.stopped) { 'stopped' } elseif ($code -eq 0) { 'done' } else { 'failed' })
        Add-ActionHistory $r.act $state $code $text
        if (-not $advWin.IsVisible -and -not $r.stopped) {
            $short = ($r.act.text -replace '\s+', ' ')
            if ($short.Length -gt 120) { $short = $short.Substring(0, 120) + '…' }
            if ($code -eq 0) { $notify.ShowBalloonTip(10000, 'Clawd', ((T 'act.balloonOk') -f $short), [System.Windows.Forms.ToolTipIcon]::Info) }
            else { $notify.ShowBalloonTip(15000, 'Clawd', ((T 'act.balloonBad') -f $short, $code), [System.Windows.Forms.ToolTipIcon]::Warning) }
        }
        Update-Panel
    }
}

# Every main tick (and right after one is added): pick up finished runs, start
# what is due. Clawd's waits while the chat is busy - one message at a time.
function Update-Actions {
    Collect-ActionRuns
    $now = Get-Date
    $changed = $false
    foreach ($a in (Get-Actions)) {
        if ($a.at -gt $now) { break }
        if ($a.at -lt $script:ActStart.AddMinutes(-$ActionLate)) {
            try { Remove-Item -LiteralPath $a.path -Force } catch { continue }
            Add-ActionHistory $a 'missed'
            $changed = $true
            continue
        }
        if ($a.kind -eq 'command') { Start-ActionRun $a; $changed = $true; continue }
        if ($script:ChatProc) { continue }
        try { Remove-Item -LiteralPath $a.path -Force } catch { continue }
        Add-ActionHistory $a 'sent'
        Send-ChatMessage ((T 'act.chatMsg') -f $a.text)
        $changed = $true
    }
    if ($changed) { Update-Panel }
}

# A command's end is picked up faster than the main tick.
$actTimer = New-Object System.Windows.Threading.DispatcherTimer
$actTimer.Interval = [TimeSpan]::FromMilliseconds(500)
$actTimer.add_Tick({
    try {
        Collect-ActionRuns
        if (-not $script:ActRuns.Count) { $actTimer.Stop() }
    } catch {
        $actTimer.Stop()
        try {
            "$(Get-Date -Format s)`tactions: $($_.Exception.Message)`t$($_.InvocationInfo.PositionMessage)" |
                Out-File (Join-Path $script:Root 'widget-error.log') -Append -Encoding utf8
        } catch {}
    }
})
