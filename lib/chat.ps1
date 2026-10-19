# ------------------------------------------------------------------ chat ----
# Talking to Clawd: every message is one headless `claude -p` call in a separate
# conversation of its own (--session-id first, then --resume). Claude may look
# around but not change anything (--permission-mode default, no write tools, only
# read-only cmdlets allowed); changes come as a `run` script the user approves
# with a click, reminders as a `remind` block the widget turns into a file.
# It runs in Clawd's home folder (Get-ClawdHome). The rules for Claude are in
# chat-prompt.md.

$ChatStatePath  = Join-Path $script:Root 'chat-state.json'
$ChatPromptPath = Join-Path $script:Root 'chat-prompt.md'
$ChatReadOnly   = @('Get-PSDrive', 'Get-Volume', 'Get-ChildItem', 'Get-Item', 'Get-ItemProperty', 'Get-Content',
                    'Get-Process', 'Get-Service', 'Get-CimInstance', 'Get-ScheduledTask', 'Get-Date', 'Test-Path',
                    'Measure-Object', 'Select-Object', 'Sort-Object', 'Where-Object', 'Format-Table', 'Format-List')
$ChatKeep       = 60     # messages kept for display

$script:ChatProc   = $null   # running claude: @{ proc; out; err; hidden }
$script:RunProc    = $null   # running approved script: @{ proc; out; err; msg }
$script:ChatUnread = $false  # Clawd answered while the panel was closed
$script:AutoChain  = 0       # scripts run by themselves since the user's last message
$AutoChainMax      = 3

function Load-JsonFile([string]$path) {
    try { return [System.IO.File]::ReadAllText($path, [System.Text.Encoding]::UTF8) | ConvertFrom-Json } catch { return $null }
}

function Save-JsonFile([string]$path, $obj) {
    try { ConvertTo-Json -InputObject $obj -Depth 6 | Out-File $path -Encoding utf8 } catch {}
}

# Messages: @{ role = user|clawd|note; text; run = @{ script; state = pending|running|done|skipped|replaced; code } }
function Load-Chat {
    # since - when "+" was pressed: the phone conversation before it is not shown.
    $c = @{ sessionId = $null; started = $false; since = [datetime]::MinValue
            messages = New-Object System.Collections.ArrayList }
    $raw = Load-JsonFile $ChatStatePath
    if ($raw) {
        $c.sessionId = $raw.sessionId
        $c.started   = [bool]$raw.started
        if ($raw.since) { try { $c.since = [datetime]$raw.since } catch {} }
        foreach ($m in @($raw.messages)) {
            if (-not $m) { continue }
            $msg = @{ role = [string]$m.role; text = [string]$m.text; at = [datetime]::MinValue }
            if ($m.task) { $msg.task = [string]$m.task }
            if ($m.at) { try { $msg.at = [datetime]$m.at } catch {} }
            if ($m.run) {
                $state = [string]$m.run.state
                # A script cannot outlive the widget: one "running" at exit is unknown now.
                if ($state -eq 'running') { $state = 'done' }
                $msg.run = @{ script = [string]$m.run.script; state = $state; code = $m.run.code }
            }
            if ($m.grant) {
                $msg.grant = @{ task = [string]$m.grant.task; state = [string]$m.grant.state
                                rules = @($m.grant.rules | Where-Object { $_ } | ForEach-Object { [string]$_ }) }
            }
            if ($m.act) {
                $msg.act = @{ state = [string]$m.act.state
                              calls = @($m.act.calls | Where-Object { $_ } | ForEach-Object { @{ tool = [string]$_.tool; input = [string]$_.input } }) }
            }
            [void]$c.messages.Add($msg)
        }
    }
    if (-not $c.sessionId) { $c.sessionId = [guid]::NewGuid().ToString() }
    return $c
}

function Save-Chat {
    while ($script:Chat.messages.Count -gt $ChatKeep) { $script:Chat.messages.RemoveAt(0) }
    Save-JsonFile $ChatStatePath @{ sessionId = $script:Chat.sessionId; started = $script:Chat.started
                                    since = $script:Chat.since.ToString('s')
                                    messages = @($script:Chat.messages | ForEach-Object {
                                        $o = @{} + $_; $o.at = $_.at.ToString('s'); $o }) }
    Write-ChatLog
}

# The panel's conversation as a file in Clawd's home - so that his own session
# (the phone) knows what was said here.
function Write-ChatLog {
    $lines = @('# Chat in the widget panel', '',
               'The user talks to Clawd here too: in the panel of the clawd-usage-winwidget widget on the PC.',
               'Written by the widget, latest at the bottom; do not edit.', '')
    foreach ($m in $script:Chat.messages) {
        if ($m.role -notin @('user', 'clawd', 'remind')) { continue }
        $who = @{ user = 'User'; clawd = 'Clawd'; remind = 'Reminder fired' }[$m.role]
        $when = $(if ($m.at -ne [datetime]::MinValue) { $m.at.ToString('yyyy-MM-dd HH:mm') } else { '' })
        $text = $m.text
        if ($m.run) { $text += "`n[proposed a script: $($m.run.state)$(if ($null -ne $m.run.code) { ", exit $($m.run.code)" })]" }
        if ($m.act) { $text += "`n[asked to use $(@($m.act.calls | ForEach-Object { $_.tool }) -join ', '): $($m.act.state)]" }
        $lines += "**$who** $when"
        $lines += $text
        $lines += ''
    }
    try {
        [System.IO.File]::WriteAllText((Join-Path (Get-ClawdHome) 'chat-log.md'), ($lines -join "`r`n"),
                                       (New-Object System.Text.UTF8Encoding $false))
    } catch {}
}

$script:Chat = Load-Chat

function Add-ChatMessage([string]$role, [string]$text, $run = $null) {
    $m = @{ role = $role; text = $text; at = Get-Date }
    if ($run) { $m.run = $run }
    [void]$script:Chat.messages.Add($m)
    Save-Chat
    return $m
}

# ------------------------------------------------- the phone conversation ----
# Clawd's own session (Remote Control) keeps its conversation in
# projects\<home>\<id>.jsonl in Claude Code's folder. The panel shows it in the same feed, and
# the panel's chat gets its latest part as context. Only what was added since the
# last look is read: the file grows by the whole conversation, tool output included.

$script:Remote = @{ path = ''; offset = [int64]0; items = New-Object System.Collections.ArrayList }
$RemoteKeep = 40

function Update-RemoteFeed {
    $id = Get-ClawdSessionId
    if (-not $id) { return }
    $key  = [regex]::Replace((Get-ClawdHome), '[^A-Za-z0-9]', '-')
    $path = [System.IO.Path]::Combine((Get-ClaudeConfigDir), "projects\$key\$id.jsonl")
    $r = $script:Remote
    if ($path -ne $r.path) { $r.path = $path; $r.offset = 0; $r.items.Clear() }
    if (-not [System.IO.File]::Exists($path)) { return }
    $len = (New-Object System.IO.FileInfo $path).Length
    if ($len -lt $r.offset) { $r.offset = 0; $r.items.Clear() }
    if ($len -eq $r.offset) { return }
    $bytes = $null
    try {
        $fs = New-Object System.IO.FileStream $path, 'Open', 'Read', 'ReadWrite'
        try {
            [void]$fs.Seek($r.offset, 'Begin')
            $bytes = New-Object byte[] ($len - $r.offset)
            $n = 0
            while ($n -lt $bytes.Length) {
                $got = $fs.Read($bytes, $n, $bytes.Length - $n)
                if ($got -le 0) { break }
                $n += $got
            }
        } finally { $fs.Dispose() }
    } catch { return }
    # Only whole lines: the last one may still be being written.
    $end = [Array]::LastIndexOf($bytes, [byte]10)
    if ($end -lt 0) { return }
    $r.offset += $end + 1
    $text = [System.Text.Encoding]::UTF8.GetString($bytes, 0, $end)
    foreach ($line in $text -split "`n") {
        # Cheap filters first: most lines are tool calls and their output.
        if ($line -notmatch '"type":"(user|assistant)"' -or $line -match '"tool_result"' -or $line -match '"isMeta":true') { continue }
        try { $j = $line | ConvertFrom-Json } catch { continue }
        if ($j.type -notin @('user', 'assistant') -or $j.isSidechain) { continue }
        $c = $j.message.content
        $say = ''
        if ($c -is [string]) { $say = $c }
        else { $say = (@($c | Where-Object { $_.type -eq 'text' } | ForEach-Object { $_.text }) -join "`n`n") }
        $say = ConvertTo-PlainText $say
        # Commands, caveats and reminders injected by Claude Code are not words.
        if (-not $say -or $say.StartsWith('<')) { continue }
        $at = [datetime]::MinValue
        try { $at = [datetime]::Parse($j.timestamp, $null, 'RoundtripKind').ToLocalTime() } catch {}
        $role = $(if ($j.type -eq 'user') { 'user' } else { 'clawd' })
        $last = $(if ($r.items.Count) { $r.items[$r.items.Count - 1] } else { $null })
        # Several text pieces between tool calls make one reply.
        if ($role -eq 'clawd' -and $last -and $last.role -eq 'clawd') { $last.text += "`n`n$say"; continue }
        if ($at -lt $script:Chat.since) { continue }
        [void]$r.items.Add(@{ role = $role; text = $say; at = $at; remote = $true })
    }
    while ($r.items.Count -gt $RemoteKeep) { $r.items.RemoveAt(0) }
}

# What Claude gets before each message: time, rights, tips with details, reminders.
function Get-ChatContext {
    $now = Get-Date
    $tz = [TimeZoneInfo]::Local.GetUtcOffset($now)
    $lines = @('<context>',
               "now: $($now.ToString('yyyy-MM-dd HH:mm dddd', [System.Globalization.CultureInfo]::InvariantCulture)) (UTC$(if ($tz -ge [TimeSpan]::Zero) { '+' } else { '-' })$($tz.ToString('hh\:mm')))",
               "widget elevated: $(if ($script:IsAdmin) { 'yes' } else { 'no' })",
               "auto-run: $(if ($script:Cfg.chatAutoRun) { 'on - your run scripts start at once, without the user''s click' } else { 'off' })",
               "full access: $(if ($script:Cfg.chatBypass) { 'on - nothing is refused, read files anywhere on the computer' } else { 'off' })")
    $tips = @(Get-AdvisorTips)
    if ($tips.Count) {
        $lines += 'tips:'
        foreach ($t in $tips) {
            $lines += "- $($t.text)"
            if ($t.ctx) { $lines += "  details: $($t.ctx)" }
        }
    } else {
        $lines += 'tips: none'
    }
    $rem = Get-Reminders
    if (-not $script:Cfg.showReminders) {
        $lines += 'reminders: turned off by the user in Settings - do not set or offer any'
    } elseif ($rem.Count) {
        $lines += 'reminders (file in the reminders folder - time - text):'
        foreach ($r in $rem) {
            $rep = $(if ($r.repeat) { " (repeats $($r.repeat))" } else { '' })
            $lines += "- $($r.rel) - $($r.at.ToString('yyyy-MM-dd HH:mm'))$rep - $($r.text)"
        }
    } else {
        $lines += 'reminders: none'
    }
    $names = Get-Lists
    if (-not $script:Cfg.showLists) {
        $lines += 'lists: turned off by the user in Settings - do not keep any'
    } elseif ($names.Count) {
        $lines += 'lists (files in the lists folder; "[x]" - ticked off):'
        foreach ($n in $names) {
            $items = @((Read-List $n).items | ForEach-Object { "$(if ($_.done) { '[x] ' })$($_.text)" })
            $lines += "- $n`: $(if ($items.Count) { $items -join '; ' } else { 'empty' })"
        }
    }
    $tasks = Get-Tasks
    if (-not $script:Cfg.showTasks) {
        $lines += 'recurring tasks: turned off by the user in Settings - they do not run; do not make any'
    } elseif ($tasks.Count) {
        $st = Load-TaskState
        $lines += 'recurring tasks (files in the tasks folder):'
        foreach ($t in $tasks) {
            $last = $(if ($st[$t.name] -and $st[$t.name].last -ne [datetime]::MinValue) { $st[$t.name].last.ToString('MM-dd HH:mm') } else { 'never' })
            $when = $(if ($t.at) { "at $($t.atText)" } else { "every $($t.everyText)" })
            $lines += "- $($t.name): $when$(if ($t.tools.Count) { ", tools $($t.tools -join ' ')" })$(if ($t.hours) { ", hours $($t.hours -join '-')" })$(if ($t.paused) { ', paused' }), last run $last - $(($t.prompt -replace '\s+', ' '))"
        }
    }
    $acts = Get-Actions
    if ($script:Cfg.showActions -and $acts.Count) {
        $lines += 'actions the user saved to run with a click (files in the actions folder; command - run by the widget itself, clawd - sent to you as a message):'
        foreach ($a in $acts) { $lines += "- $($a.name) ($($a.kind)): $(($a.text -replace '\s+', ' '))" }
    }
    # Task reports are put into the panel by the widget, not said in this conversation:
    # without them "move it to the trash" right after a mail report means nothing.
    $since = (Get-Date).AddHours(-24)
    # Before 1.3.0 reports carried no mark, only "[task name] " in front.
    $reports = @($script:Chat.messages | Where-Object { ($_.task -or ($_.role -eq 'clawd' -and $_.text -match '^\[[^\]]+\] ')) -and $_.at -gt $since } |
                 Select-Object -Last 5)
    if ($reports.Count) {
        $lines += 'recent reports of your recurring tasks, shown to the user in this chat (the user may be replying to them):'
        foreach ($m in $reports) {
            $t = $m.text -replace '\s+', ' '
            if ($t.Length -gt 800) { $t = $t.Substring(0, 800) + '...' }
            $lines += "- $($m.at.ToString('MM-dd HH:mm')) $t"
        }
    }
    $recent = @($script:Remote.items | Select-Object -Last 12)
    if ($recent.Count) {
        $lines += 'recent conversation in your own session (the user on the phone via Remote Control):'
        foreach ($m in $recent) {
            $t = $m.text -replace '\s+', ' '
            if ($t.Length -gt 400) { $t = $t.Substring(0, 400) + '...' }
            $lines += "- $($m.at.ToString('MM-dd HH:mm')) $(if ($m.role -eq 'user') { 'user' } else { 'you' }): $t"
        }
    }
    $lines += '</context>'
    return $lines -join "`n"
}

# The chat's rules for the tasks' tools. In auto mode - the whole server, as the
# task has it. Otherwise only what reads (list_*, get_*...): an action (move a
# letter, mark it read, send) is refused by Claude Code, and the widget turns the
# refusal into a card the user approves with a click (Collect-ChatReply).
$ChatReadVerbs = @('list', 'get', 'read', 'search', 'fetch', 'find', 'query', 'view', 'show')
function Get-ChatToolRules([string[]]$tools) {
    $rules = @()
    foreach ($t in $tools) {
        if ($script:Cfg.chatAutoRun -or $t -notmatch '^mcp__' -or $t -match '^mcp__.+__') { $rules += $t; continue }
        foreach ($v in $ChatReadVerbs) { $rules += "$($t)__$($v)_*" }
    }
    return ,$rules
}

# chat-prompt.md for the current mode: `compact` parts (short replies, quick checks)
# or `full` ones (a full agent, no time limit), the other kind cut out.
function Get-ChatPromptFile {
    $drop = $(if ($script:Cfg.chatCompact) { 'full' } else { 'compact' })
    $text = [System.IO.File]::ReadAllText($ChatPromptPath)
    $text = $text -replace "(?s)<!-- $drop -->.*?<!-- /$drop -->\r?\n", '' -replace '<!-- /?(compact|full) -->\r?\n', ''
    $path = Join-Path $env:TEMP "cuw-chat-prompt-$PID.md"
    [System.IO.File]::WriteAllText($path, $text, (New-Object System.Text.UTF8Encoding $false))
    return $path
}

# The chat's own time limit: none for the full agent - the user stops it from the panel.
function Test-ChatTimedOut($c) {
    return ($script:Cfg.chatCompact -and
            ([datetime]::Now - $c.at).TotalSeconds -gt [double]$script:Cfg.chatTimeoutSeconds)
}

# The stop button in place of Send stops the reply, with the tools it started.
function Stop-ChatReply {
    $c = $script:ChatProc
    if (-not $c) { return }
    try { & taskkill.exe /PID $c.proc.Id /T /F 2>&1 | Out-Null } catch {}
    $script:ChatProc = $null
    [void](Add-ChatMessage 'note' (T 'chat.stopped'))
    Update-Panel
}

# $hidden - a message from the widget itself (a script's output), not shown as the user's.
# $allow - tools allowed for this one call only (actions the user just approved).
function Send-ChatMessage([string]$text, [switch]$Hidden, [string[]]$Allow = @()) {
    if ($script:ChatProc -or -not $text.Trim()) { return }
    if (-not $Hidden) {
        # A new word from the user replaces a script still waiting for approval.
        foreach ($m in $script:Chat.messages) {
            if ($m.run -and $m.run.state -eq 'pending') { $m.run.state = 'replaced' }
            if ($m.act -and $m.act.state -eq 'pending') { $m.act.state = 'replaced' }
        }
        $script:AutoChain = 0
        [void](Add-ChatMessage 'user' $text)
    }
    try {
        $home_ = Get-ClawdHome
        $in  = Join-Path $env:TEMP "cuw-chat-in-$PID.txt"
        $out = Join-Path $env:TEMP "cuw-chat-out-$PID.json"
        $err = Join-Path $env:TEMP "cuw-chat-err-$PID.txt"
        # What the user gave the tasks (the mail...) the chat may use too: it is the same
        # Clawd, and he is asked to act on what the tasks report. No such tools - no
        # MCP servers at all, they only slow the start down.
        $tools = @(Get-Tasks | ForEach-Object { $_.tools } | Where-Object { $_ } | Sort-Object -Unique)
        $ctx = Get-ChatContext
        if ($tools.Count) {
            $how = $(if ($script:Cfg.chatAutoRun) { 'all of them at once' } else { 'reading at once; actions after the user approves them' })
            $ctx = $ctx -replace '</context>$', "tools you may use besides reading: $($tools -join ' ') ($how)`n</context>"
        }
        [System.IO.File]::WriteAllText($in, $ctx + "`n`n" + $text, (New-Object System.Text.UTF8Encoding $false))
        $q = { param($s) '"' + $s + '"' }
        $argv = @('-p', '--output-format', 'stream-json', '--verbose', '--model', [string]$script:Cfg.chatModel,
                  '--permission-mode', $(if ($script:Cfg.chatBypass) { 'bypassPermissions' } else { 'default' }))
        if (-not $tools.Count) { $argv += '--strict-mcp-config' }
        $argv += @('--disallowedTools', 'Write', 'Edit', 'NotebookEdit',
                   '--append-system-prompt-file', (& $q (Get-ChatPromptFile)),
                   '--allowedTools') + @($ChatReadOnly | ForEach-Object { & $q "PowerShell($_`:*)" }) +
                 @((Get-ChatToolRules $tools) + $Allow | ForEach-Object { & $q $_ })
        if ($script:Chat.started) { $argv += @('--resume', $script:Chat.sessionId) }
        else                      { $argv += @('--session-id', $script:Chat.sessionId) }
        $p = Start-Process -FilePath $script:ClaudeExe -WorkingDirectory $home_ -ArgumentList $argv `
                 -RedirectStandardInput $in -RedirectStandardOutput $out -RedirectStandardError $err `
                 -WindowStyle Hidden -PassThru
        [void]$p.Handle
        $script:ChatProc = @{ proc = $p; out = $out; err = $err; at = Get-Date; offset = [int64]0; doing = '' }
        $chatTimer.Start()
    } catch {
        [void](Add-ChatMessage 'note' ((T 'chat.error') -f $_.Exception.Message))
    }
    Update-Panel
}

# Pulls `run`, `remind` and `remind-cancel` blocks out of the reply; the rest is the text.
function Read-ChatReply([string]$reply) {
    $run = $null
    $notes = @()
    $rx = [regex]'(?ms)^```(run|remind|remind-cancel|list-add|list-check|list-uncheck|list-remove|task|task-remove)[ \t]*\r?\n(.*?)^```[ \t]*$'
    $skipped = @()
    foreach ($m in $rx.Matches($reply)) {
        $body = $m.Groups[2].Value.Trim()
        # A block for a part turned off in Settings is not acted on.
        $off = switch -regex ($m.Groups[1].Value) {
            '^remind'  { if (-not $script:Cfg.showReminders) { 'showReminders' } }
            '^list-'   { if (-not $script:Cfg.showLists) { 'showLists' } }
            '^task'    { if (-not $script:Cfg.showTasks) { 'showTasks' } }
        }
        if ($off) {
            if ($skipped -notcontains $off) { $skipped += $off; $notes += (T 'chat.moduleOff') -f (T "set.$off") }
            continue
        }
        switch ($m.Groups[1].Value) {
            'run' { if ($body) { $run = @{ script = $body; state = 'pending'; code = $null } } }
            'remind' {
                foreach ($line in $body -split '\r?\n') {
                    $parts = $line -split '\|', 2
                    if ($parts.Count -lt 2) { continue }
                    # "2026-11-17T10:00 monthly | text": a repeat word may follow the time.
                    $when = @($parts[0].Trim() -split '\s+')
                    try { $at = [datetime]::Parse($when[0], [System.Globalization.CultureInfo]::InvariantCulture) } catch { continue }
                    $repeat = $(if ($when.Count -gt 1 -and $RemindRepeats -contains $when[1].ToLower()) { $when[1].ToLower() } else { '' })
                    $what = $parts[1].Trim()
                    [void](New-ReminderFile $at $what $repeat)
                    $set = Format-RemindTime $at
                    if ($repeat) { $set += ", $(T "rem.$repeat")" }
                    $notes += (T 'chat.remindSet') -f $set, $what
                }
            }
            { $_ -like 'list-*' } {
                # "<list> | <item>" per line; a new list is made by adding to it.
                $kind = $_
                foreach ($line in $body -split '\r?\n') {
                    $parts = $line -split '\|', 2
                    if ($parts.Count -lt 2 -or -not $parts[0].Trim() -or -not $parts[1].Trim()) { continue }
                    $list = Get-ListName $parts[0]; $item = $parts[1].Trim()
                    $ok = $true
                    switch ($kind) {
                        'list-add'     { Add-ListItems $list $item }
                        'list-check'   { $ok = Set-ListItemDone $list $item $true }
                        'list-uncheck' { $ok = Set-ListItemDone $list $item $false }
                        'list-remove'  { $ok = Remove-ListItem $list $item }
                    }
                    if ($ok) { $notes += (T "chat.$kind") -f $list, $item }
                }
            }
            'remind-cancel' {
                foreach ($line in $body -split '\r?\n') {
                    if (-not $line.Trim()) { continue }
                    $r = Remove-Reminder $line
                    if ($r) { $notes += (T 'chat.remindCancel') -f $r.text }
                }
            }
            'task' {
                # "key: value" lines (name, every or at, tools, model, hours), "---", then the task text.
                $parts = [regex]::Split($body, '(?m)^---[ \t]*\r?$\n?', 2)
                if ($parts.Count -lt 2) { break }
                $head = @{}
                foreach ($line in $parts[0] -split '\r?\n') {
                    $kv = [regex]::Match($line, '^\s*(\w+)\s*:\s*(.*?)\s*$')
                    if ($kv.Success) { $head[$kv.Groups[1].Value.ToLower()] = $kv.Groups[2].Value }
                }
                $sched = @{ every = Read-TaskEvery ([string]$head.every); at = $(if ($head.at) { Read-TaskAt ([string]$head.at) }) }
                if (-not $head.name -or -not ($sched.every -or $sched.at) -or -not $parts[1].Trim()) {
                    $notes += (T 'chat.taskBad') -f $head.name
                    break
                }
                if (New-TaskFile $head.name $head $parts[1]) { $notes += (T 'chat.taskSet') -f $head.name, (Format-TaskWhen $sched) }
            }
            'task-remove' {
                foreach ($line in $body -split '\r?\n') {
                    if (-not $line.Trim()) { continue }
                    $t = Remove-TaskFile $line
                    if ($t) { $notes += (T 'chat.taskRemove') -f $t.name }
                }
            }
        }
    }
    $text = ConvertTo-PlainText ($rx.Replace($reply, ''))
    return @{ text = $text; run = $run; notes = $notes }
}

# The panel shows plain text: drop markdown emphasis and inline code marks.
function ConvertTo-PlainText([string]$text) {
    $text = $text -replace '\*\*(.+?)\*\*', '$1' -replace '`([^`]+)`', '$1'
    return ($text -replace '(\r?\n){3,}', "`n`n").Trim()
}

# What Clawd is busy with, from one content block of the stream: "Reading win.ini",
# "Running: Get-ChildItem..."; $null - nothing to show.
function Get-ChatDoing($b) {
    $cut = { param($s) $s = ([string]$s -split "`r?`n")[0].Trim(); if ($s.Length -gt 44) { $s.Substring(0, 44).TrimEnd() } else { $s } }
    switch ([string]$b.type) {
        'thinking' { return T 'chat.doing.think' }
        'text'     { return T 'chat.doing.write' }
        'tool_use' { }
        default    { return $null }
    }
    $in = $b.input
    $name = [string]$b.name
    switch -regex ($name) {
        '^Read$'              { return (T 'chat.doing.read') -f (& $cut ([System.IO.Path]::GetFileName([string]$in.file_path))) }
        '^(Glob|Grep)$'       { return (T 'chat.doing.search') -f (& $cut $in.pattern) }
        '^(PowerShell|Bash)$' { return (T 'chat.doing.run') -f (& $cut $in.command) }
        '^WebFetch$'          { try { return (T 'chat.doing.fetch') -f ([uri][string]$in.url).Host } catch { return T 'chat.doing.web' } }
        '^WebSearch$'         { return (T 'chat.doing.websearch') -f (& $cut $in.query) }
        '^(Task|Agent)$'      { return T 'chat.doing.agent' }
        '^mcp__([^_]+(?:_[^_]+)*)__(.+)$' { return (T 'chat.doing.tool') -f "$($Matches[1]): $($Matches[2])" }
        default               { return (T 'chat.doing.tool') -f $name }
    }
}

# Reads what the stream added since the last look (whole lines only) and keeps the
# latest action in $ChatProc.doing. A tool's result means he is thinking again.
function Update-ChatActivity {
    $c = $script:ChatProc
    if (-not $c) { return }
    $buf = $null; $n = 0
    try {
        $fs = New-Object System.IO.FileStream($c.out, 'Open', 'Read', 'ReadWrite, Delete')
        try {
            if ($fs.Length -le $c.offset) { return }
            $fs.Position = $c.offset
            $buf = New-Object byte[] ([int]($fs.Length - $c.offset))
            $n = $fs.Read($buf, 0, $buf.Length)
        } finally { $fs.Close() }
    } catch { return }
    if ($n -le 0) { return }
    $end = [array]::LastIndexOf($buf, [byte]10, $n - 1)
    if ($end -lt 0) { return }
    $c.offset += $end + 1
    foreach ($line in ([System.Text.Encoding]::UTF8.GetString($buf, 0, $end) -split "`n")) {
        if ($line.StartsWith('{"type":"user"')) { $c.doing = ''; continue }
        if (-not $line.StartsWith('{"type":"assistant"')) { continue }
        try { $j = $line | ConvertFrom-Json } catch { continue }
        foreach ($b in @($j.message.content)) {
            $d = Get-ChatDoing $b
            if ($d) { $c.doing = $d }
        }
    }
}

# The stream's last word: the `result` line, the same object `--output-format json` gives.
function Read-ChatResult([string]$path) {
    $lines = [System.IO.File]::ReadAllText($path, [System.Text.Encoding]::UTF8) -split "`n"
    for ($i = $lines.Count - 1; $i -ge 0; $i--) {
        if ($lines[$i] -match '"type":"result"') { return $lines[$i] | ConvertFrom-Json }
    }
    return $null
}

function Collect-ChatReply {
    $c = $script:ChatProc
    if (-not $c) { return }
    # Stuck (a tool scanning a whole drive, a hung command) - stop it with its children.
    if (-not $c.proc.HasExited -and (Test-ChatTimedOut $c)) {
        try { & taskkill.exe /PID $c.proc.Id /T /F 2>&1 | Out-Null } catch {}
        $script:ChatProc = $null
        [void](Add-ChatMessage 'note' ((T 'chat.timeout') -f [int]$script:Cfg.chatTimeoutSeconds))
        Update-Panel
        return
    }
    if (-not $c.proc.HasExited) { return }
    $script:ChatProc = $null
    $j = $null
    try { $j = Read-ChatResult $c.out } catch {}
    if ($j -and -not $j.is_error -and $null -ne $j.result) {
        $script:Chat.started = $true
        # A block that failed to parse must not swallow the reply itself.
        try { $r = Read-ChatReply ([string]$j.result) }
        catch { $r = @{ text = [string]$j.result; run = $null; notes = @((T 'chat.error') -f $_.Exception.Message) } }
        # Actions Claude Code refused for want of permission: a card for the user to approve.
        $calls = @($j.permission_denials | Where-Object { $_ -and ([string]$_.tool_name).StartsWith('mcp__') } | ForEach-Object {
            @{ tool = [string]$_.tool_name; input = (ConvertTo-Json -InputObject $_.tool_input -Depth 6 -Compress) } })
        $msg = $null
        if ($r.text -or $r.run -or $calls.Count) { $msg = Add-ChatMessage 'clawd' $r.text $r.run }
        if ($calls.Count) { $msg.act = @{ state = 'pending'; calls = $calls }; Save-Chat }
        foreach ($n in $r.notes) { [void](Add-ChatMessage 'note' $n) }
        # Auto mode: the script runs without a click, but only a few in a row on their
        # own - Clawd answering each result with yet another script stops for a word from the user.
        if ($msg -and $msg.run -and $script:Cfg.chatAutoRun) {
            if ($script:AutoChain -lt $AutoChainMax) { $script:AutoChain++; Start-ChatRun $msg }
            else { [void](Add-ChatMessage 'note' ((T 'chat.autoStop') -f $AutoChainMax)) }
        }
    } else {
        $why = ''
        if ($j -and $j.result) { $why = [string]$j.result }
        if (-not $why) { try { $why = ([System.IO.File]::ReadAllText($c.err)).Trim() } catch {} }
        if (-not $why) { $why = "exit $($c.proc.ExitCode)" }
        if ($why.Length -gt 300) { $why = $why.Substring(0, 300) + '…' }
        [void](Add-ChatMessage 'note' ((T 'chat.error') -f $why))
    }
    if (-not $advWin.IsVisible) {
        $script:ChatUnread = $true
        $m = $script:Mz
        if ($script:Cfg.showMascot -and -not $m.act -and -not $m.buried -and $m.mood -ne 'dead') { Start-MascotAct 'wave' }
    }
    Update-Panel
    Update-Badge
}

# ----------------------------------------------------- approved scripts ----

function Start-ChatRun($msg) {
    if ($script:RunProc -or $script:ChatProc -or -not $msg.run -or $msg.run.state -ne 'pending') { return }
    try {
        $ps1 = Join-Path $env:TEMP "cuw-run-$PID.ps1"
        $out = Join-Path $env:TEMP "cuw-run-out-$PID.txt"
        $err = Join-Path $env:TEMP "cuw-run-err-$PID.txt"
        # With BOM: PowerShell 5.1 reads a file without one as ANSI. Output in UTF-8,
        # not the console's OEM code page - otherwise Cyrillic comes back garbled.
        $body = "[Console]::OutputEncoding = [System.Text.Encoding]::UTF8`r`n" + $msg.run.script
        [System.IO.File]::WriteAllText($ps1, $body, (New-Object System.Text.UTF8Encoding $true))
        $p = Start-Process -FilePath (Join-Path $PSHOME 'powershell.exe') `
                 -ArgumentList '-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass', '-File', "`"$ps1`"" `
                 -RedirectStandardOutput $out -RedirectStandardError $err -WindowStyle Hidden -PassThru
        # Taking the handle now keeps ExitCode readable after the process ends.
        [void]$p.Handle
        $msg.run.state = 'running'
        $script:RunProc = @{ proc = $p; out = $out; err = $err; msg = $msg }
        Save-Chat
        $chatTimer.Start()
    } catch {
        [void](Add-ChatMessage 'note' ((T 'chat.error') -f $_.Exception.Message))
    }
    Update-Panel
}

function Collect-ChatRun {
    $r = $script:RunProc
    if (-not $r -or -not $r.proc.HasExited) { return }
    $script:RunProc = $null
    $code = $r.proc.ExitCode
    $r.msg.run.state = 'done'
    $r.msg.run.code  = $code
    Save-Chat
    $text = ''
    foreach ($f in @($r.out, $r.err)) { try { $text += [System.IO.File]::ReadAllText($f, [System.Text.Encoding]::UTF8) } catch {} }
    $text = $text.Trim()
    if ($text.Length -gt 3000) { $text = '…' + $text.Substring($text.Length - 3000) }
    # Claude sums up what happened; the space numbers in the tips are stale now.
    Send-ChatMessage -Hidden "[run result] exit code $code`n$text"
    Start-AdvisorScan
}

function Set-RunState($msg, [string]$state) {
    if ($msg.run -and $msg.run.state -eq 'pending') { $msg.run.state = $state; Save-Chat; Update-Panel }
}

# ---------------------------------------------------- approved tool calls ----
# Clawd asked to act with a tool (move a letter, send one...) and was refused: on
# "Run" the same conversation goes on with exactly those tools allowed, once.

function Approve-ChatAct($msg) {
    if ($script:ChatProc -or -not $msg.act -or $msg.act.state -ne 'pending') { return }
    $msg.act.state = 'approved'
    Save-Chat
    $list = @($msg.act.calls | ForEach-Object { "- $($_.tool) $($_.input)" }) -join "`n"
    Send-ChatMessage -Hidden -Allow @($msg.act.calls | ForEach-Object { $_.tool } | Sort-Object -Unique) `
        "[approved] The user clicked Run: make exactly these calls now, then say briefly what came of them.`n$list"
}

function Set-ActState($msg, [string]$state) {
    if ($msg.act -and $msg.act.state -eq 'pending') { $msg.act.state = $state; Save-Chat; Update-Panel }
}

# "+" in the panel: a new conversation here, and the phone conversation so far is
# no longer shown. Clawd's own session is left alone: restarting it would add a
# second entry to the Remote Control list on the phone. There `/clear` starts a
# new conversation in the same entry, and the feed follows it (the session id in
# the registry changes, Update-ClawdSession picks it up).
function Reset-Chat {
    if ($script:ChatProc) { return }
    $script:Chat = @{ sessionId = [guid]::NewGuid().ToString(); started = $false; since = Get-Date
                      messages = New-Object System.Collections.ArrayList }
    Save-Chat
    $script:Remote.items.Clear()
    Update-Panel -Force
}

# The reply and a script's end are picked up faster than the main tick.
$chatTimer = New-Object System.Windows.Threading.DispatcherTimer
$chatTimer.Interval = [TimeSpan]::FromMilliseconds(500)
$chatTimer.add_Tick({
    try {
        Collect-ChatRun
        Update-ChatActivity
        Collect-ChatReply
        if (-not $script:ChatProc -and -not $script:RunProc) { $chatTimer.Stop() }
        Update-PanelBusy
    } catch {
        $chatTimer.Stop()
        try {
            "$(Get-Date -Format s)`tchat: $($_.Exception.Message)`t$($_.InvocationInfo.PositionMessage)" |
                Out-File (Join-Path $script:Root 'widget-error.log') -Append -Encoding utf8
        } catch {}
    }
})
