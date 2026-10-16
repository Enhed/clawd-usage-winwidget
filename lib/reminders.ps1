# ------------------------------------------------------------- reminders ----
# Reminders are plain files in Clawd's home, so that anyone can make one: the chat
# in the panel (through the widget), Clawd's own session from the phone (writes the
# file itself), or the user by hand.
#   reminders\2026-11\2026-11-16 10-00 Pay the taxes.md
#   ---
#   at: 2026-11-16T10:00
#   ---
#   Pay the taxes
# The widget looks at the folder every tick and fires what is due: a Windows
# notification, a bell in the header, Clawd hops. Fired ones go to reminders\done.

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
        try { $notify.ShowBalloonTip(15000, (T 'chat.remindTitle'), $text, [System.Windows.Forms.ToolTipIcon]::Info) } catch {}
        $m = $script:Mz
        if ($script:Cfg.showMascot -and -not $m.buried -and $m.mood -ne 'dead') { Start-MascotAct 'jump' }
        Update-Panel
    }
}
