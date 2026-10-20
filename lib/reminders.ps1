# ------------------------------------------------------------- reminders ----
# Reminders are plain files in Clawd's home, so that anyone can make one: the chat
# in the panel (through the widget), Clawd's own session from the phone (writes the
# file itself), or the user by hand.
#   reminders\2026-11\2026-11-16 10-00 Pay the taxes.md
#   ---
#   at: 2026-11-16T10:00
#   repeat: monthly         (optional: daily, weekly, monthly, yearly)
#   ---
#   Pay the taxes
# The widget looks at the folder every tick and fires what is due: a card to put
# it off or mark done (remind-popup.ps1), a bell in the header, Clawd hops.
# Fired ones go to reminders\done; a repeating one leaves a file for its next time.

$RemindRepeats = @('daily', 'weekly', 'monthly', 'yearly')

$script:RemindDue   = @()     # fired reminders not seen yet
$script:RemindFired = @{}     # paths fired in this run - in case moving the file failed

function Get-RemindersDir { return Join-Path (Get-ClawdHome) 'reminders' }

function Format-RemindTime([datetime]$at) {
    $c = Get-LangCulture
    if ($at.Date -eq (Get-Date).Date) { return $at.ToString('HH:mm', $c) }
    return $at.ToString('ddd d MMM HH:mm', $c)
}

# The first time after $after: the series goes on from $at, the widget may have been off.
function Get-NextRemindTime([datetime]$at, [string]$repeat, [datetime]$after) {
    # Steps from $at, so the time of day stays. A monthly one on the 29th-31st
    # goes on from the shorter month's last day.
    for ($k = 1; $k -lt 100000; $k++) {
        $next = switch ($repeat) {
            'daily'   { $at.AddDays($k) }
            'weekly'  { $at.AddDays(7 * $k) }
            'monthly' { $at.AddMonths($k) }
            'yearly'  { $at.AddYears($k) }
        }
        if ($next -gt $after) { return $next }
    }
    return $null
}

# Active reminders, soonest first: @{ path; rel; at; text; repeat }.
function Get-Reminders {
    $root = Get-RemindersDir
    $list = @()
    if (-not [System.IO.Directory]::Exists($root)) { return ,$list }
    foreach ($f in @(Get-ChildItem $root -Recurse -File -Filter *.md -ErrorAction SilentlyContinue)) {
        $rel = $f.FullName.Substring($root.Length + 1)
        if ($rel -like 'done\*' -or $script:RemindFired[$f.FullName]) { continue }
        $at = $null; $text = ''; $repeat = ''
        try {
            $raw = [System.IO.File]::ReadAllText($f.FullName, [System.Text.Encoding]::UTF8)
            $m = [regex]::Match($raw, '(?s)^\s*---\s*\r?\n(.*?)\r?\n---\s*\r?\n?(.*)$')
            if ($m.Success) {
                $a = [regex]::Match($m.Groups[1].Value, '(?m)^\s*at:\s*(\S+)')
                if ($a.Success) { try { $at = [datetime]::Parse($a.Groups[1].Value, [System.Globalization.CultureInfo]::InvariantCulture) } catch {} }
                $rp = [regex]::Match($m.Groups[1].Value, '(?m)^\s*repeat:\s*(\w+)')
                if ($rp.Success -and $RemindRepeats -contains $rp.Groups[1].Value.ToLower()) { $repeat = $rp.Groups[1].Value.ToLower() }
                $text = $m.Groups[2].Value.Trim()
            } else {
                $text = $raw.Trim()
            }
        } catch { continue }
        # No "at:" - the time from the file name.
        $n = [regex]::Match($f.BaseName, '^(\d{4}-\d{2}-\d{2})[ T](\d{2})-(\d{2})\s*(.*)$')
        if (-not $at -and $n.Success) {
            try { $at = [datetime]::ParseExact("$($n.Groups[1].Value) $($n.Groups[2].Value):$($n.Groups[3].Value)", 'yyyy-MM-dd HH:mm', $null) } catch {}
        }
        if (-not $at) { continue }
        if (-not $text) { $text = $(if ($n.Success) { $n.Groups[4].Value } else { $f.BaseName }) }
        $list += @{ path = $f.FullName; rel = $rel; at = $at; text = $text; repeat = $repeat }
    }
    $list = @($list | Sort-Object { $_.at })
    return ,$list
}

function New-ReminderFile([datetime]$at, [string]$text, [string]$repeat = '') {
    $dir = Join-Path (Get-RemindersDir) $at.ToString('yyyy-MM')
    [void][System.IO.Directory]::CreateDirectory($dir)
    $title = ($text -replace '[\\/:*?"<>|\r\n]', ' ' -replace '\s+', ' ').Trim()
    if ($title.Length -gt 50) { $title = $title.Substring(0, 50).Trim() }
    $base = "$($at.ToString('yyyy-MM-dd HH-mm')) $title"
    $path = Join-Path $dir "$base.md"
    $i = 2
    while (Test-Path $path) { $path = Join-Path $dir "$base ($i).md"; $i++ }
    $rep = $(if ($RemindRepeats -contains $repeat) { "repeat: $repeat`n" } else { '' })
    $body = "---`nat: $($at.ToString('yyyy-MM-ddTHH:mm'))`n$rep---`n$text`n"
    [System.IO.File]::WriteAllText($path, $body, (New-Object System.Text.UTF8Encoding $false))
    return $path
}

# By path relative to the reminders folder, or just by file name.
function Remove-Reminder([string]$name) {
    $name = $name.Trim().Trim('"').Replace('/', '\')
    foreach ($r in (Get-Reminders)) {
        if ($r.rel -eq $name -or (Split-Path -Leaf $r.path) -eq $name -or
            [System.IO.Path]::GetFileNameWithoutExtension($r.path) -eq $name) {
            try { Remove-Item -LiteralPath $r.path -Force; return $r } catch {}
        }
    }
    return $null
}

function Update-Reminders {
    $now = Get-Date
    foreach ($r in (Get-Reminders)) {
        if ($r.at -gt $now) { break }
        $script:RemindFired[$r.path] = $true
        $to = $null
        try {
            $done = Join-Path (Join-Path (Get-RemindersDir) 'done') $r.at.ToString('yyyy-MM')
            [void][System.IO.Directory]::CreateDirectory($done)
            $to = Join-Path $done (Split-Path -Leaf $r.path)
            if (Test-Path $to) { Remove-Item -LiteralPath $to -Force }
            Move-Item -LiteralPath $r.path -Destination $to
        } catch {}
        if ($r.repeat) {
            $next = Get-NextRemindTime $r.at $r.repeat $now
            if ($next) { try { [void](New-ReminderFile $next $r.text $r.repeat) } catch {} }
        }
        $text = $r.text
        # The widget was off at the time - say when it was due.
        if (($now - $r.at).TotalMinutes -gt 5) { $text = (T 'chat.remindLate') -f $text, (Format-RemindTime $r.at) }
        [void](Add-ChatMessage 'remind' $text)
        $script:RemindDue += $r
        # A card with "later" and "done" instead of a plain Windows notification.
        try { Show-RemindPopup $r $to $text } catch {
            $notify.ShowBalloonTip(15000, (T 'chat.remindTitle'), $text, [System.Windows.Forms.ToolTipIcon]::Info)
        }
        $m = $script:Mz
        if ($script:Cfg.showMascot -and -not $m.buried -and $m.mood -ne 'dead') { Start-MascotAct 'jump' }
        Update-Panel
    }
}

# Moving one is a new file for the new time: the time is in the file name too.
# A repeating one keeps repeating, from the new time.
function Move-Reminder($r, [datetime]$at, [string]$text = $null) {
    if (-not $text) { $text = $r.text }
    try { Remove-Item -LiteralPath $r.path -Force } catch {}
    return New-ReminderFile $at $text $r.repeat
}

# Recently fired ones, newest first.
function Get-DoneReminders([int]$count = 5) {
    $done = Join-Path (Get-RemindersDir) 'done'
    $list = @()
    foreach ($f in @(Get-ChildItem $done -Recurse -File -Filter *.md -ErrorAction SilentlyContinue |
                     Sort-Object Name -Descending | Select-Object -First $count)) {
        $n = [regex]::Match($f.BaseName, '^(\d{4}-\d{2}-\d{2})[ T](\d{2})-(\d{2})\s*(.*)$')
        if (-not $n.Success) { continue }
        $at = [datetime]::ParseExact("$($n.Groups[1].Value) $($n.Groups[2].Value):$($n.Groups[3].Value)", 'yyyy-MM-dd HH:mm', $null)
        $text = $n.Groups[4].Value
        try {
            $m = [regex]::Match([System.IO.File]::ReadAllText($f.FullName, [System.Text.Encoding]::UTF8), '(?s)^\s*---.*?\r?\n---\s*\r?\n?(.*)$')
            if ($m.Success -and $m.Groups[1].Value.Trim()) { $text = $m.Groups[1].Value.Trim() }
        } catch {}
        $list += @{ at = $at; text = $text }
    }
    return ,$list
}

# "In N units": +20m, in 2 hours, через час, через неделю, dans une semaine. A word
# in front ("in", "через", "dans") may stand for one. Returns @{ n; unit = min|hour|day|week|month } or $null.
function Read-RemindOffset([string]$s) {
    $m = [regex]::Match($s, '^(\+|через |in |dans )?\s*(\d+|an?|une?)?\s*(m|min|mins|minutes?|м|мин\w*|полчаса|h|hours?|heures?|ч|час\w*|d|days?|jours?|д|дн\w*|день|w|weeks?|semaines?|н|нед\w*|mo|months?|mois|мес\w*)$')
    if (-not $m.Success) { return $null }
    $num = $m.Groups[2].Value
    if ($num -match '^\d+$') { $n = [int]$num }
    elseif ($m.Groups[1].Value.Trim() -in @('через', 'in', 'dans')) { $n = 1 }
    else { return $null }
    $u = $m.Groups[3].Value
    $unit = $(if ($u -eq 'полчаса') { 'half' } elseif ($u -match '^(mo|мес)') { 'month' } elseif ($u -match '^(w|н|sem)') { 'week' }
              elseif ($u -match '^(m|м)') { 'min' } elseif ($u -match '^(h|ч)') { 'hour' } else { 'day' })
    return @{ n = $n; unit = $unit }
}

# "When" as people write it: 18:30, tomorrow 10:00, +20m, in 2 hours, mon 9:00,
# через неделю 15:00, demain 18h30, 19.10 14:00, 19.10.2026, 2026-10-19 14:00. A day without a
# time is 10:00; a time already gone today is tomorrow. $null - not understood
# (the panel then asks Claude, see Start-WhenProbe).
function ConvertFrom-RemindWhen([string]$s) {
    $s = $s.Trim().ToLower() -replace '\s+', ' '
    if (-not $s) { return $null }
    $now = Get-Date
    $time = { param($h, $m) [timespan]::new([int]$h, [int]$(if ($m) { $m } else { 0 }), 0) }

    $o = Read-RemindOffset $s
    if ($o -and $o.unit -eq 'half') { return $now.AddMinutes(30 * $o.n) }
    if ($o -and $o.unit -eq 'min')  { return $now.AddMinutes($o.n) }
    if ($o -and $o.unit -eq 'hour') { return $now.AddHours($o.n) }
    # Optional time at the end: "... 9", "... 9:30", "... 9.30", "... 9h", "... 9h30".
    $t = $null
    $tm = [regex]::Match($s, '(?:^|\s)(?:в |at |à )?(\d{1,2})(?:[:.h](\d{2})|h)?$')
    $rest = $s
    if ($tm.Success -and [int]$tm.Groups[1].Value -lt 24) {
        $t = & $time $tm.Groups[1].Value $tm.Groups[2].Value
        $rest = $s.Substring(0, $tm.Index).Trim()
    }
    if (-not $rest) {
        if (-not $t -or -not $tm.Groups[2].Value) { return $null }   # a bare number is not a time
        $at = $now.Date + $t
        if ($at -le $now) { $at = $at.AddDays(1) }
        return $at
    }
    if (-not $t) { $t = & $time 10 0 }
    $o = Read-RemindOffset $rest
    if ($o -and $o.unit -eq 'day')   { return $now.Date.AddDays($o.n) + $t }
    if ($o -and $o.unit -eq 'week')  { return $now.Date.AddDays(7 * $o.n) + $t }
    if ($o -and $o.unit -eq 'month') { return $now.Date.AddMonths($o.n) + $t }
    if ($rest -in @('сегодня', 'today', "aujourd'hui", "aujourd’hui")) { return $now.Date + $t }
    if ($rest -in @('завтра', 'tomorrow', 'demain'))     { return $now.Date.AddDays(1) + $t }
    if ($rest -in @('послезавтра', 'après-demain'))      { return $now.Date.AddDays(2) + $t }
    $days = @{ 'пн' = 1; 'вт' = 2; 'ср' = 3; 'чт' = 4; 'пт' = 5; 'сб' = 6; 'вс' = 0
               'пон' = 1; 'вто' = 2; 'сре' = 3; 'чет' = 4; 'пят' = 5; 'суб' = 6; 'вос' = 0
               'mon' = 1; 'tue' = 2; 'wed' = 3; 'thu' = 4; 'fri' = 5; 'sat' = 6; 'sun' = 0
               'lun' = 1; 'mar' = 2; 'mer' = 3; 'jeu' = 4; 'ven' = 5; 'sam' = 6; 'dim' = 0 }
    $w = $rest -replace '^(в|во|on|le) ', ''
    $key = $(if ($w.Length -ge 3 -and $days.ContainsKey($w.Substring(0, 3))) { $w.Substring(0, 3) }
             elseif ($w.Length -ge 2 -and $days.ContainsKey($w.Substring(0, 2))) { $w.Substring(0, 2) })
    if ($key) {
        $d = ($days[$key] - [int]$now.DayOfWeek + 7) % 7
        $at = $now.Date.AddDays($d) + $t
        if ($at -le $now) { $at = $at.AddDays(7) }
        return $at
    }
    $dm = [regex]::Match($rest, '^(\d{1,2})\.(\d{1,2})(?:\.(\d{2}|\d{4}))?$')
    if ($dm.Success) {
        $y = $(if ($dm.Groups[3].Value) { [int]$dm.Groups[3].Value } else { $now.Year })
        if ($y -lt 100) { $y += 2000 }
        try { $at = (Get-Date -Year $y -Month ([int]$dm.Groups[2].Value) -Day ([int]$dm.Groups[1].Value)).Date + $t } catch { return $null }
        if (-not $dm.Groups[3].Value -and $at -le $now) { $at = $at.AddYears(1) }
        return $at
    }
    $iso = [regex]::Match($rest, '^(\d{4})-(\d{2})-(\d{2})$')
    if ($iso.Success) {
        try { return (Get-Date -Year ([int]$iso.Groups[1].Value) -Month ([int]$iso.Groups[2].Value) -Day ([int]$iso.Groups[3].Value)).Date + $t } catch { return $null }
    }
    return $null
}

# What the parser above does not know ("in a week and a half", "on the 1st of
# November", "next Friday evening") goes to a small model: one `claude -p` with no
# tools, outside Clawd's home, answering with a date or NONE. $kind 'task' - the
# Tasks form's "how often" ("twice an hour in the daytime"): the answer is a
# schedule in the form's own words, checked by Read-TaskSchedule.
$script:WhenProc = $null   # @{ proc; out; at; when; data; kind }

function Start-WhenProbe([string]$when, $data, [string]$kind = 'remind') {
    if ($script:WhenProc) { return $false }
    try {
        $now = Get-Date
        $tz  = [TimeZoneInfo]::Local.GetUtcOffset($now)
        $in  = Join-Path $env:TEMP "cuw-when-in-$PID.txt"
        $out = Join-Path $env:TEMP "cuw-when-out-$PID.txt"
        $prompt = $(if ($kind -eq 'task') { @(
            "A user wrote how often a recurring task should run: `"$when`"",
            'Turn it into a schedule written one of these ways:',
            '- every N minutes, hours or days: 30m, 2h, 1d (2m at least);',
            '- times of day: 09:00 or 09:00, 13:30, 18:00;',
            '- minutes and hours may end with the hours to run in: 30m 8-23 (from 8:00 till 23:00).',
            'A time the user wrote is copied exactly: 21:15 stays 21:15, "in the morning at eight" is 08:00. Only where no time is given at all pick one yourself: morning 09:00, evening 19:00; daytime is 8-23.',
            'Days of the week, dates and months cannot be set. If the text needs them, or names no period or time at all, the answer is NONE - never guess.',
            'Reply with exactly one line: the schedule, or NONE.'
        ) } else { @(
            "Now: $($now.ToString('yyyy-MM-dd HH:mm dddd', [System.Globalization.CultureInfo]::InvariantCulture)) (UTC$(if ($tz -ge [TimeSpan]::Zero) { '+' } else { '-' })$($tz.ToString('hh\:mm'))).",
            "A user wrote when a reminder should go off: `"$when`"",
            'Turn it into a local date and time. A day without a time is 10:00; a time already gone today is tomorrow.',
            'If the text names no day, date, time or period at all (it is a task, a word, gibberish), the answer is NONE - never guess.',
            'Reply with exactly one line: the time as yyyy-MM-ddTHH:mm, or NONE.'
        ) }) -join "`n"
        [System.IO.File]::WriteAllText($in, $prompt, (New-Object System.Text.UTF8Encoding $false))
        $argv = @('-p', '--output-format', 'text', '--model', [string]$script:Cfg.quickModel,
                  '--tools', '""', '--strict-mcp-config', '--no-session-persistence')
        $p = Start-Process -FilePath $script:ClaudeExe -WorkingDirectory $env:TEMP -ArgumentList $argv `
                 -RedirectStandardInput $in -RedirectStandardOutput $out -WindowStyle Hidden -PassThru
        [void]$p.Handle
        $script:WhenProc = @{ proc = $p; out = $out; at = $now; when = $when; data = $data; kind = $kind }
        return $true
    } catch { return $false }
}

# $null while it is still thinking; then @{ at = <datetime or $null>; when; data }, for
# a task @{ sched = <Read-TaskSchedule's result or $null>; when; data }.
function Collect-WhenProbe {
    $w = $script:WhenProc
    if (-not $w) { return $null }
    if (-not $w.proc.HasExited) {
        if (([datetime]::Now - $w.at).TotalSeconds -lt 60) { return $null }
        try { & taskkill.exe /PID $w.proc.Id /T /F 2>&1 | Out-Null } catch {}
    }
    $script:WhenProc = $null
    if ($w.kind -eq 'task') {
        $s = $null
        try {
            $line = @([System.IO.File]::ReadAllText($w.out, [System.Text.Encoding]::UTF8) -split '\r?\n' |
                      ForEach-Object { $_.Trim().Trim('`', '"', '.') } | Where-Object { $_ })[0]
            if ($line -and $line -notmatch '^NONE$') { $s = Read-TaskSchedule $line }
        } catch {}
        return @{ sched = $s; when = $w.when; data = $w.data }
    }
    $at = $null
    try {
        $m = [regex]::Match([System.IO.File]::ReadAllText($w.out, [System.Text.Encoding]::UTF8), '\d{4}-\d{2}-\d{2}T\d{2}:\d{2}')
        if ($m.Success) { $at = [datetime]::ParseExact($m.Value, 'yyyy-MM-ddTHH:mm', $null) }
    } catch {}
    # A time in the past is no answer either.
    if ($at -and $at -lt (Get-Date).AddMinutes(-1)) { $at = $null }
    return @{ at = $at; when = $w.when; data = $w.data }
}
