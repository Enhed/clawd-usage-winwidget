# ------------------------------------------------------------- reminders ----
# Reminders are plain files in Clawd's home, so that anyone can make one: the chat
# in the panel (through the widget), Clawd's own session from the phone (writes the
# file itself), or the user by hand.
#   reminders\2026-11\2026-11-16 10-00 Pay the taxes.md
#   ---
#   at: 2026-11-16T10:00
#   ---
#   Pay the taxes
# The widget looks at the folder every tick and fires what is due: a card to put
# it off or mark done (remind-popup.ps1), a bell in the header, Clawd hops.
# Fired ones go to reminders\done.

$script:RemindDue   = @()     # fired reminders not seen yet
$script:RemindFired = @{}     # paths fired in this run - in case moving the file failed

function Get-RemindersDir { return Join-Path (Get-ClawdHome) 'reminders' }

function Get-LangCulture {
    if ((Get-Lang) -eq 'ru') { return [System.Globalization.CultureInfo]::GetCultureInfo('ru-RU') }
    return [System.Globalization.CultureInfo]::GetCultureInfo('en-US')
}

function Format-RemindTime([datetime]$at) {
    $c = Get-LangCulture
    if ($at.Date -eq (Get-Date).Date) { return $at.ToString('HH:mm', $c) }
    return $at.ToString('ddd d MMM HH:mm', $c)
}

# Active reminders, soonest first: @{ path; rel; at; text }.
function Get-Reminders {
    $root = Get-RemindersDir
    $list = @()
    if (-not [System.IO.Directory]::Exists($root)) { return ,$list }
    foreach ($f in @(Get-ChildItem $root -Recurse -File -Filter *.md -ErrorAction SilentlyContinue)) {
        $rel = $f.FullName.Substring($root.Length + 1)
        if ($rel -like 'done\*' -or $script:RemindFired[$f.FullName]) { continue }
        $at = $null; $text = ''
        try {
            $raw = [System.IO.File]::ReadAllText($f.FullName, [System.Text.Encoding]::UTF8)
            $m = [regex]::Match($raw, '(?s)^\s*---\s*\r?\n(.*?)\r?\n---\s*\r?\n?(.*)$')
            if ($m.Success) {
                $a = [regex]::Match($m.Groups[1].Value, '(?m)^\s*at:\s*(\S+)')
                if ($a.Success) { try { $at = [datetime]::Parse($a.Groups[1].Value, [System.Globalization.CultureInfo]::InvariantCulture) } catch {} }
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
        $list += @{ path = $f.FullName; rel = $rel; at = $at; text = $text }
    }
    $list = @($list | Sort-Object { $_.at })
    return ,$list
}

function New-ReminderFile([datetime]$at, [string]$text) {
    $dir = Join-Path (Get-RemindersDir) $at.ToString('yyyy-MM')
    [void][System.IO.Directory]::CreateDirectory($dir)
    $title = ($text -replace '[\\/:*?"<>|\r\n]', ' ' -replace '\s+', ' ').Trim()
    if ($title.Length -gt 50) { $title = $title.Substring(0, 50).Trim() }
    $base = "$($at.ToString('yyyy-MM-dd HH-mm')) $title"
    $path = Join-Path $dir "$base.md"
    $i = 2
    while (Test-Path $path) { $path = Join-Path $dir "$base ($i).md"; $i++ }
    $body = "---`nat: $($at.ToString('yyyy-MM-ddTHH:mm'))`n---`n$text`n"
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
function Move-Reminder($r, [datetime]$at, [string]$text = $null) {
    if (-not $text) { $text = $r.text }
    try { Remove-Item -LiteralPath $r.path -Force } catch {}
    return New-ReminderFile $at $text
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

# "When" as people write it: 18:30, tomorrow 10:00, +20m, in 2 hours, mon 9:00,
# 19.10 14:00, 19.10.2026, 2026-10-19 14:00. A day without a time is 10:00;
# a time already gone today is tomorrow. $null - not understood.
function ConvertFrom-RemindWhen([string]$s) {
    $s = $s.Trim().ToLower() -replace '\s+', ' '
    if (-not $s) { return $null }
    $now = Get-Date
    $time = { param($h, $m) [timespan]::new([int]$h, [int]$(if ($m) { $m } else { 0 }), 0) }

    $m = [regex]::Match($s, '^(?:\+|через |in )?\s*(\d+)\s*(m|min|mins|minutes?|м|мин\w*|h|hours?|ч|час\w*|d|days?|д|дн\w*|день)$')
    if ($m.Success) {
        $n = [int]$m.Groups[1].Value; $u = $m.Groups[2].Value
        if ($u -match '^(m|min|м)') { return $now.AddMinutes($n) }
        if ($u -match '^(h|ч)')     { return $now.AddHours($n) }
        return $now.Date.AddDays($n) + (& $time 10 0)
    }
    # Optional time at the end: "... 9", "... 9:30", "... 9.30".
    $t = $null
    $tm = [regex]::Match($s, '(?:^|\s)(?:в |at )?(\d{1,2})(?:[:.](\d{2}))?$')
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
    if ($rest -in @('сегодня', 'today'))                 { return $now.Date + $t }
    if ($rest -in @('завтра', 'tomorrow'))               { return $now.Date.AddDays(1) + $t }
    if ($rest -in @('послезавтра'))                      { return $now.Date.AddDays(2) + $t }
    $days = @{ 'пн' = 1; 'вт' = 2; 'ср' = 3; 'чт' = 4; 'пт' = 5; 'сб' = 6; 'вс' = 0
               'пон' = 1; 'вто' = 2; 'сре' = 3; 'чет' = 4; 'пят' = 5; 'суб' = 6; 'вос' = 0
               'mon' = 1; 'tue' = 2; 'wed' = 3; 'thu' = 4; 'fri' = 5; 'sat' = 6; 'sun' = 0 }
    $w = $rest -replace '^(в|во|on) ', ''
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
