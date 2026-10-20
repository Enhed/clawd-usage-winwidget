# --------------------------------------------------------------- actions ----
# Actions: saved things to do once, on a click - a command or a mini-skill for
# Clawd. Plain files in Clawd's home, like reminders and tasks:
#   actions\Backup.md
#   ---
#   kind: command           (or clawd)
#   ---
#   C:\Tools\backup.cmd
# `command` - the widget runs it itself, no Claude: a program, a file or a folder is
# opened, anything else is a PowerShell script; its exit code and output are kept.
# `clawd` - the words go to the chat, and Clawd does it the chat's way (his `run`
# script waits for a click unless auto-run is on); while the chat is busy it waits.

$ActionsStatePath = Join-Path $script:Root 'actions-state.json'
$ActionKinds      = @('clawd', 'command')
$ActionKeep       = 20       # history lines kept

$script:ActRuns  = New-Object System.Collections.ArrayList   # @{ proc; out; err; ps1; at; act; stopped }
$script:ActQueue = New-Object System.Collections.ArrayList   # Clawd's, waiting for the chat
$script:ActSeq   = 0

function Get-ActionsDir { return Join-Path (Get-ClawdHome) 'actions' }

# Saved actions, by name: @{ name; path; kind; text }.
function Get-Actions {
    $list = @()
    $dir = Get-ActionsDir
    if (-not [System.IO.Directory]::Exists($dir)) { return ,$list }
    foreach ($f in @(Get-ChildItem $dir -File -Filter *.md -ErrorAction SilentlyContinue | Sort-Object Name)) {
        try { $raw = [System.IO.File]::ReadAllText($f.FullName, [System.Text.Encoding]::UTF8) } catch { continue }
        $a = @{ name = $f.BaseName; path = $f.FullName; kind = 'clawd'; text = $raw.Trim() }
        $m = [regex]::Match($raw, '(?s)^\s*---\s*\r?\n(.*?)\r?\n---\s*\r?\n?(.*)$')
        if ($m.Success) {
            $a.text = $m.Groups[2].Value.Trim()
            $k = [regex]::Match($m.Groups[1].Value, '(?m)^\s*kind:\s*(\w+)')
            if ($k.Success -and $ActionKinds -contains $k.Groups[1].Value.ToLower()) { $a.kind = $k.Groups[1].Value.ToLower() }
        }
        if (-not $a.text) { continue }
        $list += $a
    }
    return ,$list
}

function Find-Action([string]$name) {
    foreach ($a in (Get-Actions)) { if ($a.name -eq $name) { return $a } }
    return $null
}

# Made or changed from the panel's form; $old - the one being changed (renamed, maybe).
function Save-ActionFile([string]$name, [string]$kind, [string]$text, $old) {
    $file = ($name -replace '[\\/:*?"<>|\r\n]', ' ' -replace '\s+', ' ').Trim()
    if (-not $file) { return $null }
    $dir = Get-ActionsDir
    [void][System.IO.Directory]::CreateDirectory($dir)
    $path = Join-Path $dir "$file.md"
    $body = "---`nkind: $kind`n---`n$($text.Trim())`n"
    [System.IO.File]::WriteAllText($path, $body, (New-Object System.Text.UTF8Encoding $false))
    if ($old -and $old.path -ne $path) { try { Remove-Item -LiteralPath $old.path -Force } catch {} }
    return $file
}

# History, newest last: @{ at; name; kind; text; state = done|failed|sent|stopped; code; output }.
function Load-ActionHistory {
    $list = @()
    $raw = Load-JsonFile $ActionsStatePath
    foreach ($h in @($(if ($raw) { $raw.history }))) {
        if (-not $h) { continue }
        try {
            $list += @{ at = [datetime]$h.at; name = [string]$h.name; kind = [string]$h.kind; text = [string]$h.text
                        state = [string]$h.state; code = $h.code; output = [string]$h.output }
        } catch {}
    }
    return ,$list
}

function Add-ActionHistory($a, [string]$state, $code = $null, [string]$output = '') {
    # Not @(Load-ActionHistory): it hands the list over as one object.
    $list = Load-ActionHistory
    $list += @{ at = Get-Date; name = $a.name; kind = $a.kind; text = $a.text; state = $state; code = $code; output = $output }
    $list = @($list | Select-Object -Last $ActionKeep)
    Save-JsonFile $ActionsStatePath @{ history = @($list | ForEach-Object {
        @{ at = $_.at.ToString('s'); name = $_.name; kind = $_.kind; text = $_.text
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

# The same action is not run twice at once: a click while it runs or waits does nothing.
function Get-ActionRun([string]$name) {
    if (-not $name) { return $null }
    foreach ($r in $script:ActRuns) { if ($r.act.name -eq $name) { return $r } }
    return $null
}

function Test-ActionQueued([string]$name) {
    return ($name -and @($script:ActQueue | Where-Object { $_.name -eq $name }).Count -gt 0)
}

# A click on Run: $a - a saved one, or @{ name = ''; kind; text } straight from the form.
function Invoke-Action($a) {
    if ((Get-ActionRun $a.name) -or (Test-ActionQueued $a.name)) { return }
    if ($a.kind -eq 'command') { Start-ActionRun $a }
    else { [void]$script:ActQueue.Add($a); Send-ActionQueue }
    Update-Panel
}

# Clawd's go to the chat one by one, when it is free.
function Send-ActionQueue {
    if ($script:ChatProc -or -not $script:ActQueue.Count) { return }
    $a = $script:ActQueue[0]
    $script:ActQueue.RemoveAt(0)
    Add-ActionHistory $a 'sent'
    $msg = $(if ($a.name) { (T 'act.chatMsg') -f $a.name, $a.text } else { $a.text })
    Send-ChatMessage $msg
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
        $p = Start-JobProcess (Join-Path $PSHOME 'powershell.exe') `
                 @('-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass', '-File', "`"$ps1`"") $env:USERPROFILE '' $out $err
        [void]$script:ActRuns.Add(@{ proc = $p; out = $out; err = $err; ps1 = $ps1; at = Get-Date; act = $a; stopped = $false })
        $actTimer.Start()
    } catch {
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
        # A long one may end with the panel closed.
        if (-not $advWin.IsVisible -and -not $r.stopped) {
            $short = $(if ($r.act.name) { $r.act.name } else { $r.act.text -replace '\s+', ' ' })
            if ($short.Length -gt 120) { $short = $short.Substring(0, 120) + '…' }
            if ($code -eq 0) { $notify.ShowBalloonTip(10000, 'Clawd', ((T 'act.balloonOk') -f $short), [System.Windows.Forms.ToolTipIcon]::Info) }
            else { $notify.ShowBalloonTip(15000, 'Clawd', ((T 'act.balloonBad') -f $short, $code), [System.Windows.Forms.ToolTipIcon]::Warning) }
        }
        Update-Panel
    }
}

# Every main tick: pick up finished commands, hand a waiting one to the chat.
function Update-Actions {
    Collect-ActionRuns
    if ($script:ActQueue.Count -and -not $script:ChatProc) { Send-ActionQueue; Update-Panel }
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
