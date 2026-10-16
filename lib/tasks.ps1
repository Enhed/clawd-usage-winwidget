# ----------------------------------------------------------------- tasks ----
# Recurring tasks: something Clawd does by himself every so often - look at the
# mail, check a site, keep an eye on a folder. Plain files in Clawd's home, like
# reminders, so the chat, his phone session or the user can make one:
#   tasks\Mail.md
#   ---
#   every: 10m
#   tools: mcp__mail
#   hours: 8-23
#   ---
#   Check the inbox for new mail since the last run. Tell me only about ...
# The widget runs a due one as a headless `claude -p` in Clawd's home with the
# usual context plus its previous report (tasks-prompt.md has the rules). The
# reply NOTHING means nothing to say; anything else lands in the chat with a
# notification. A `run` script from a task always waits for a click.
# `tools` - what it may use besides reading (an MCP server as mcp__<name>);
# `model` - instead of quickModel; `hours` - only between these hours;
# `limit` - wait while the plan's usage is at this percent or more (instead of
# tasksMaxPercent); `paused: yes` - kept, but not run.

$TasksStatePath  = Join-Path $script:Root 'tasks-state.json'
$TasksPromptPath = Join-Path $script:Root 'tasks-prompt.md'
$script:TaskProc = $null   # @{ proc; out; err; at; task }

function Get-TasksDir { return Join-Path (Get-ClawdHome) 'tasks' }

# "10m", "2h", "1d", "30 мин" -> TimeSpan; at least two minutes.
function Read-TaskEvery([string]$s) {
    $m = [regex]::Match($s.Trim().ToLower(), '^(\d+)\s*(m|min|mins|minutes?|м|мин\w*|h|hours?|ч|час\w*|d|days?|д|дн\w*|день)$')
    if (-not $m.Success) { return $null }
    $n = [int]$m.Groups[1].Value; $u = $m.Groups[2].Value
    $span = $(if ($u -match '^(m|м)') { [timespan]::FromMinutes($n) } elseif ($u -match '^(h|ч)') { [timespan]::FromHours($n) } else { [timespan]::FromDays($n) })
    if ($span.TotalMinutes -lt 2) { $span = [timespan]::FromMinutes(2) }
    return $span
}

function Format-TaskEvery([timespan]$span) {
    if ($span.TotalDays -ge 1 -and $span.TotalDays -eq [math]::Floor($span.TotalDays)) { return (T 'task.everyD') -f $span.TotalDays }
    if ($span.TotalHours -ge 1 -and $span.TotalHours -eq [math]::Floor($span.TotalHours)) { return (T 'task.everyH') -f $span.TotalHours }
    return (T 'task.everyM') -f [int]$span.TotalMinutes
}

# All tasks, by name: @{ name; path; every; everyText; tools; model; hours; paused; prompt }.
function Get-Tasks {
    $list = @()
    $dir = Get-TasksDir
    if (-not [System.IO.Directory]::Exists($dir)) { return ,$list }
    foreach ($f in @(Get-ChildItem $dir -File -Filter *.md -ErrorAction SilentlyContinue | Sort-Object Name)) {
        try { $raw = [System.IO.File]::ReadAllText($f.FullName, [System.Text.Encoding]::UTF8) } catch { continue }
        $t = @{ name = $f.BaseName; path = $f.FullName; every = $null; everyText = ''; tools = @(); model = ''
                hours = $null; limit = $null; paused = $false; prompt = $raw.Trim() }
        $m = [regex]::Match($raw, '(?s)^\s*---\s*\r?\n(.*?)\r?\n---\s*\r?\n?(.*)$')
        if ($m.Success) {
            $t.prompt = $m.Groups[2].Value.Trim()
            foreach ($line in $m.Groups[1].Value -split '\r?\n') {
                $kv = [regex]::Match($line, '^\s*(\w+)\s*:\s*(.*?)\s*$')
                if (-not $kv.Success) { continue }
                $v = $kv.Groups[2].Value
                switch ($kv.Groups[1].Value.ToLower()) {
                    'every'  { $t.everyText = $v; $t.every = Read-TaskEvery $v }
                    'tools'  { $t.tools = @($v -split '[,\s]+' | Where-Object { $_ }) }
                    'model'  { $t.model = $v }
                    'paused' { $t.paused = ($v -match '^(yes|true|1|да)$') }
                    'limit'  { $l = [regex]::Match($v, '^(\d{1,3})\s*%?$'); if ($l.Success) { $t.limit = [int]$l.Groups[1].Value } }
                    'hours'  {
                        $h = [regex]::Match($v, '^(\d{1,2})(?::00)?\s*-\s*(\d{1,2})(?::00)?$')
                        if ($h.Success) { $t.hours = @([int]$h.Groups[1].Value, [int]$h.Groups[2].Value) }
                    }
                }
            }
        }
        $list += $t
    }
    return ,$list
}

function Test-TaskHours($t) {
    if (-not $t.hours) { return $true }
    $h = (Get-Date).Hour; $a = $t.hours[0]; $b = $t.hours[1]
    if ($a -le $b) { return ($h -ge $a -and $h -lt $b) }
    return ($h -ge $a -or $h -lt $b)    # across midnight: 22-7
}

# Made or replaced from the chat's `task` block.
function New-TaskFile([string]$name, [hashtable]$head, [string]$prompt) {
    $dir = Get-TasksDir
    [void][System.IO.Directory]::CreateDirectory($dir)
    $file = ($name -replace '[\\/:*?"<>|\r\n]', ' ' -replace '\s+', ' ').Trim()
    if (-not $file) { return $null }
    $lines = @('---')
    foreach ($k in @('every', 'tools', 'model', 'hours', 'limit', 'paused')) { if ($head[$k]) { $lines += "${k}: $($head[$k])" } }
    $lines += @('---', $prompt.Trim(), '')
    $path = Join-Path $dir "$file.md"
    [System.IO.File]::WriteAllText($path, ($lines -join "`n"), (New-Object System.Text.UTF8Encoding $false))
    return $path
}

function Remove-TaskFile([string]$name) {
    $t = Get-Tasks | Where-Object { $_.name -eq $name.Trim() } | Select-Object -First 1
    if (-not $t) { return $null }
    try { Remove-Item -LiteralPath $t.path -Force } catch { return $null }
    $st = Load-TaskState
    if ($st.ContainsKey($t.name)) { $st.Remove($t.name); Save-TaskState $st }
    return $t
}

function Set-TaskPaused($t, [bool]$paused) {
    try {
        $raw = [System.IO.File]::ReadAllText($t.path, [System.Text.Encoding]::UTF8)
        $raw = [regex]::Replace($raw, '(?m)^\s*paused\s*:.*\r?\n', '')
        if ($paused) { $raw = [regex]::Replace($raw, '^(\s*---\s*\r?\n)', "`$1paused: yes`n") }
        [System.IO.File]::WriteAllText($t.path, $raw, (New-Object System.Text.UTF8Encoding $false))
    } catch {}
}

# name -> @{ last = when it ran; report = its last report worth telling; error;
#           history = @(@{ at; text }) - the latest reports, newest last }
$TaskHistoryKeep = 10
function Load-TaskState {
    $st = @{}
    $raw = Load-JsonFile $TasksStatePath
    if ($raw) {
        foreach ($p in $raw.PSObject.Properties) {
            $e = @{ last = [datetime]::MinValue; report = [string]$p.Value.report; error = [string]$p.Value.error; history = @() }
            if ($p.Value.last) { try { $e.last = [datetime]$p.Value.last } catch {} }
            foreach ($h in @($p.Value.history)) {
                if (-not $h) { continue }
                try { $e.history += @{ at = [datetime]$h.at; text = [string]$h.text } } catch {}
            }
            $st[$p.Name] = $e
        }
    }
    return $st
}

function Save-TaskState($st) {
    $o = @{}
    foreach ($k in $st.Keys) {
        $o[$k] = @{ last = $st[$k].last.ToString('s'); report = $st[$k].report; error = $st[$k].error
                    history = @($st[$k].history | ForEach-Object { @{ at = $_.at.ToString('s'); text = $_.text } }) }
    }
    Save-JsonFile $TasksStatePath $o
}

function Start-TaskRun($t) {
    if ($script:TaskProc -or -not $t.prompt) { return }
    $st = Load-TaskState
    $prev = $st[$t.name]
    try {
        $in  = Join-Path $env:TEMP "cuw-task-in-$PID.txt"
        $out = Join-Path $env:TEMP "cuw-task-out-$PID.json"
        $err = Join-Path $env:TEMP "cuw-task-err-$PID.txt"
        $head = @("<task name=`"$($t.name)`" every=`"$($t.everyText)`">")
        if ($prev -and $prev.last -ne [datetime]::MinValue) { $head += "last run: $($prev.last.ToString('yyyy-MM-dd HH:mm'))" }
        else { $head += 'last run: never - this is the first one' }
        if ($prev -and $prev.report) { $head += "your last report to the user:`n$($prev.report)" }
        $head += '</task>'
        $text = (Get-ChatContext) + "`n`n" + ($head -join "`n") + "`n`n" + $t.prompt
        [System.IO.File]::WriteAllText($in, $text, (New-Object System.Text.UTF8Encoding $false))
        $q = { param($s) '"' + $s + '"' }
        $model = $(if ($t.model) { $t.model } else { [string]$script:Cfg.quickModel })
        $argv = @('-p', '--output-format', 'json', '--model', $model,
                  '--permission-mode', 'default', '--no-session-persistence',
                  '--disallowedTools', 'Write', 'Edit', 'NotebookEdit',
                  '--append-system-prompt-file', (& $q $TasksPromptPath),
                  '--allowedTools') + @($ChatReadOnly | ForEach-Object { & $q "PowerShell($_`:*)" }) +
                @($t.tools | ForEach-Object { & $q $_ })
        $p = Start-Process -FilePath $script:ClaudeExe -WorkingDirectory (Get-ClawdHome) -ArgumentList $argv `
                 -RedirectStandardInput $in -RedirectStandardOutput $out -RedirectStandardError $err `
                 -WindowStyle Hidden -PassThru
        [void]$p.Handle
        $script:TaskProc = @{ proc = $p; out = $out; err = $err; at = Get-Date; task = $t }
    } catch {
        Set-TaskResult $t $null $_.Exception.Message
    }
}

# What came of a run: $report - the reply ($null on failure), $why - what went wrong.
function Set-TaskResult($t, $report, [string]$why) {
    $st = Load-TaskState
    $e = $st[$t.name]
    if (-not $e) { $e = @{ last = [datetime]::MinValue; report = ''; error = ''; history = @() }; $st[$t.name] = $e }
    $e.last = Get-Date
    if ($null -eq $report) {
        # The same failure every ten minutes is said once.
        if ($why -ne $e.error) { [void](Add-ChatMessage 'note' ((T 'task.error') -f $t.name, $why)) }
        $e.error = $why
        Save-TaskState $st
        Update-Panel
        return
    }
    $e.error = ''
    $said = ([string]$report).Trim()
    if (-not $said -or $said -match '^\W*NOTHING\W*$') { Save-TaskState $st; return }
    try { $r = Read-ChatReply $said } catch { $r = @{ text = $said; run = $null; notes = @() } }
    $e.report = $(if ($r.text.Length -gt 1500) { $r.text.Substring(0, 1500) + '…' } else { $r.text })
    $e.history = @(@($e.history) + @{ at = Get-Date; text = $e.report } | Select-Object -Last $TaskHistoryKeep)
    Save-TaskState $st
    $text = "[$($t.name)] $($r.text)"
    $msg = Add-ChatMessage 'clawd' $text $r.run
    $msg.task = $t.name
    Save-Chat
    foreach ($n in $r.notes) { [void](Add-ChatMessage 'note' $n) }
    if (-not $advWin.IsVisible) {
        $script:ChatUnread = $true
        $short = $(if ($r.text.Length -gt 200) { $r.text.Substring(0, 200) + '…' } else { $r.text })
        $notify.ShowBalloonTip(15000, "Clawd $([char]0x00B7) $($t.name)", $short, [System.Windows.Forms.ToolTipIcon]::Info)
        $m = $script:Mz
        if ($script:Cfg.showMascot -and -not $m.act -and -not $m.buried -and $m.mood -ne 'dead') { Start-MascotAct 'wave' }
    }
    Update-Panel
    Update-Badge
}

function Collect-TaskRun {
    $c = $script:TaskProc
    if (-not $c) { return }
    if (-not $c.proc.HasExited) {
        if (([datetime]::Now - $c.at).TotalSeconds -le [double]$script:Cfg.chatTimeoutSeconds) { return }
        try { & taskkill.exe /PID $c.proc.Id /T /F 2>&1 | Out-Null } catch {}
        $script:TaskProc = $null
        Set-TaskResult $c.task $null ((T 'task.timeout') -f [int]$script:Cfg.chatTimeoutSeconds)
        return
    }
    $script:TaskProc = $null
    $j = $null
    try { $j = [System.IO.File]::ReadAllText($c.out, [System.Text.Encoding]::UTF8) | ConvertFrom-Json } catch {}
    if ($j -and -not $j.is_error -and $null -ne $j.result) {
        Set-TaskResult $c.task ([string]$j.result) ''
    } else {
        $why = ''
        if ($j -and $j.result) { $why = [string]$j.result }
        if (-not $why) { try { $why = ([System.IO.File]::ReadAllText($c.err)).Trim() } catch {} }
        if (-not $why) { $why = "exit $($c.proc.ExitCode)" }
        if ($why.Length -gt 300) { $why = $why.Substring(0, 300) + '…' }
        Set-TaskResult $c.task $null $why
    }
}

# The plan's usage high - tasks wait for the window to reset, so a background mail
# check does not eat what is left for work. The higher of the five-hour session and
# the week counts; no data yet - no reason to wait. $null - may run, otherwise the
# percent it waits on.
function Get-TaskBudgetWait($t) {
    $max = $(if ($null -ne $t.limit) { [int]$t.limit } else { [int]$script:Cfg.tasksMaxPercent })
    if ($max -le 0 -or $max -ge 100) { return $null }
    $u = $script:Usage
    if (-not $u) { return $null }
    $pct = [math]::Max([int]$(if ($null -ne $u.session) { $u.session } else { 0 }), [int]$(if ($null -ne $u.week) { $u.week } else { 0 }))
    if ($pct -ge $max) { return $pct }
    return $null
}

# Every main tick: pick up a finished run, start the next due one - one at a time.
function Update-Tasks {
    Collect-TaskRun
    if (-not $script:Cfg.showTasks -or $script:TaskProc) { return }
    $st = Load-TaskState
    $now = Get-Date
    foreach ($t in (Get-Tasks)) {
        if ($t.paused -or -not $t.every -or -not (Test-TaskHours $t)) { continue }
        if ($null -ne (Get-TaskBudgetWait $t)) { continue }
        $last = $(if ($st[$t.name]) { $st[$t.name].last } else { [datetime]::MinValue })
        if (($now - $last) -ge $t.every) { Start-TaskRun $t; return }
    }
}
