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
            if ($m.at) { try { $msg.at = [datetime]$m.at } catch {} }
            if ($m.run) {
                $state = [string]$m.run.state
                # A script cannot outlive the widget: one "running" at exit is unknown now.
                if ($state -eq 'running') { $state = 'done' }
                $msg.run = @{ script = [string]$m.run.script; state = $state; code = $m.run.code }
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
# ~/.claude/projects/<home>/<id>.jsonl. The panel shows it in the same feed, and
# the panel's chat gets its latest part as context. Only what was added since the
# last look is read: the file grows by the whole conversation, tool output included.

$script:Remote = @{ path = ''; offset = [int64]0; items = New-Object System.Collections.ArrayList }
$RemoteKeep = 40

function Update-RemoteFeed {
    $id = Get-ClawdSessionId
    if (-not $id) { return }
    $key  = [regex]::Replace((Get-ClawdHome), '[^A-Za-z0-9]', '-')
    $path = Join-Path $env:USERPROFILE ".claude\projects\$key\$id.jsonl"
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
               "widget elevated: $(if ($script:IsAdmin) { 'yes' } else { 'no' })")
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
    if ($rem.Count) {
        $lines += 'reminders (file in the reminders folder - time - text):'
        foreach ($r in $rem) { $lines += "- $($r.rel) - $($r.at.ToString('yyyy-MM-dd HH:mm')) - $($r.text)" }
    } else {
        $lines += 'reminders: none'
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

# $hidden - a message from the widget itself (a script's output), not shown as the user's.
function Send-ChatMessage([string]$text, [switch]$Hidden) {
    if ($script:ChatProc -or -not $text.Trim()) { return }
    if (-not $Hidden) {
        # A new word from the user replaces a script still waiting for approval.
        foreach ($m in $script:Chat.messages) { if ($m.run -and $m.run.state -eq 'pending') { $m.run.state = 'replaced' } }
        [void](Add-ChatMessage 'user' $text)
    }
    try {
        $home_ = Get-ClawdHome
        $in  = Join-Path $env:TEMP "cuw-chat-in-$PID.txt"
        $out = Join-Path $env:TEMP "cuw-chat-out-$PID.json"
        $err = Join-Path $env:TEMP "cuw-chat-err-$PID.txt"
        [System.IO.File]::WriteAllText($in, (Get-ChatContext) + "`n`n" + $text, (New-Object System.Text.UTF8Encoding $false))
        $q = { param($s) '"' + $s + '"' }
        $argv = @('-p', '--output-format', 'json', '--model', [string]$script:Cfg.chatModel,
                  '--permission-mode', 'default', '--strict-mcp-config',
                  '--disallowedTools', 'Write', 'Edit', 'NotebookEdit',
                  '--append-system-prompt-file', (& $q $ChatPromptPath),
                  '--allowedTools') + @($ChatReadOnly | ForEach-Object { & $q "PowerShell($_`:*)" })
        if ($script:Chat.started) { $argv += @('--resume', $script:Chat.sessionId) }
        else                      { $argv += @('--session-id', $script:Chat.sessionId) }
        $p = Start-Process -FilePath $script:ClaudeExe -WorkingDirectory $home_ -ArgumentList $argv `
                 -RedirectStandardInput $in -RedirectStandardOutput $out -RedirectStandardError $err `
                 -WindowStyle Hidden -PassThru
        [void]$p.Handle
        $script:ChatProc = @{ proc = $p; out = $out; err = $err; at = Get-Date }
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
    $rx = [regex]'(?ms)^```(run|remind|remind-cancel)[ \t]*\r?\n(.*?)^```[ \t]*$'
    foreach ($m in $rx.Matches($reply)) {
        $body = $m.Groups[2].Value.Trim()
        switch ($m.Groups[1].Value) {
            'run' { if ($body) { $run = @{ script = $body; state = 'pending'; code = $null } } }
            'remind' {
                foreach ($line in $body -split '\r?\n') {
                    $parts = $line -split '\|', 2
                    if ($parts.Count -lt 2) { continue }
                    try { $at = [datetime]::Parse($parts[0].Trim(), [System.Globalization.CultureInfo]::InvariantCulture) } catch { continue }
                    $what = $parts[1].Trim()
                    [void](New-ReminderFile $at $what)
                    $notes += (T 'chat.remindSet') -f (Format-RemindTime $at), $what
                }
            }
            'remind-cancel' {
                foreach ($line in $body -split '\r?\n') {
                    if (-not $line.Trim()) { continue }
                    $r = Remove-Reminder $line
                    if ($r) { $notes += (T 'chat.remindCancel') -f $r.text }
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

function Collect-ChatReply {
    $c = $script:ChatProc
    if (-not $c) { return }
    # Stuck (a tool scanning a whole drive, a hung command) - stop it with its children.
    if (-not $c.proc.HasExited -and
        ([datetime]::Now - $c.at).TotalSeconds -gt [double]$script:Cfg.chatTimeoutSeconds) {
        try { & taskkill.exe /PID $c.proc.Id /T /F 2>&1 | Out-Null } catch {}
        $script:ChatProc = $null
        [void](Add-ChatMessage 'note' ((T 'chat.timeout') -f [int]$script:Cfg.chatTimeoutSeconds))
        Update-Panel
        return
    }
    if (-not $c.proc.HasExited) { return }
    $script:ChatProc = $null
    $j = $null
    try { $j = [System.IO.File]::ReadAllText($c.out, [System.Text.Encoding]::UTF8) | ConvertFrom-Json } catch {}
    if ($j -and -not $j.is_error -and $null -ne $j.result) {
        $script:Chat.started = $true
        # A block that failed to parse must not swallow the reply itself.
        try { $r = Read-ChatReply ([string]$j.result) }
        catch { $r = @{ text = [string]$j.result; run = $null; notes = @((T 'chat.error') -f $_.Exception.Message) } }
        if ($r.text -or $r.run) { [void](Add-ChatMessage 'clawd' $r.text $r.run) }
        foreach ($n in $r.notes) { [void](Add-ChatMessage 'note' $n) }
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
                 -ArgumentList '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$ps1`"" `
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
