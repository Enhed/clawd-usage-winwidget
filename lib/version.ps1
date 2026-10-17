# --------------------------------------------------- version and update ----
# The latest release number comes from the same place the official installer uses
# (https://claude.ai/install.ps1): downloads.claude.ai/claude-code-releases/<channel>.
# Channel - autoUpdatesChannel from Claude Code's settings.json, latest by default.

[System.Net.ServicePointManager]::SecurityProtocol =
    [System.Net.ServicePointManager]::SecurityProtocol -bor [System.Net.SecurityProtocolType]::Tls12

$script:VerLocal  = $null
$script:VerLatest = $null
$script:VerTask   = $null
$script:VerAt     = [datetime]::MinValue

function Get-UpdateChannel {
    try {
        $s = Get-Content -LiteralPath ([System.IO.Path]::Combine((Get-ClaudeConfigDir), 'settings.json')) -Raw -Encoding UTF8 | ConvertFrom-Json
        if ($s.autoUpdatesChannel -in @('stable','latest')) { return $s.autoUpdatesChannel }
    } catch {}
    return 'latest'
}

function Start-VersionProbe {
    if ($script:VerTask -and -not $script:VerTask.IsCompleted) { return }
    $script:VerAt = Get-Date
    Start-ReleaseProbe
    # Re-read the local version every time: Claude Code updates itself.
    try {
        $raw = & $script:ClaudeExe --version
        $m = [regex]::Match(($raw | Out-String), '(\d+\.\d+\.\d+)')
        if ($m.Success) { $script:VerLocal = $m.Groups[1].Value }
    } catch {}
    try {
        $wc = New-Object System.Net.WebClient
        $script:VerTask = $wc.DownloadStringTaskAsync(
            "https://downloads.claude.ai/claude-code-releases/$(Get-UpdateChannel)")
    } catch {
        $script:VerTask = $null
    }
}

function Collect-VersionProbe {
    if (-not $script:VerTask -or -not $script:VerTask.IsCompleted) { return }
    $t = $script:VerTask
    $script:VerTask = $null
    if ($t.Status -ne 'RanToCompletion') { return }
    $m = [regex]::Match([string]$t.Result, '^\s*(\d+\.\d+\.\d+)')
    if ($m.Success) { $script:VerLatest = $m.Groups[1].Value }
}

function Test-UpdateAvailable {
    if (-not $script:VerLocal -or -not $script:VerLatest) { return $false }
    try { return ([version]$script:VerLatest -gt [version]$script:VerLocal) } catch { return $false }
}

# What's new: the official CHANGELOG.md from the anthropics/claude-code repo.
# Downloaded only when an update exists, and once per new version.

$ChangelogUrl = 'https://raw.githubusercontent.com/anthropics/claude-code/main/CHANGELOG.md'

$script:Changes     = $null   # @{ for = '<latest>'; from = '<local>'; items = @() }
$script:ChangesTask = $null
$script:ChangesTry  = [datetime]::MinValue
$script:UpdateProc  = $null

function Start-ChangelogProbe {
    if (-not (Test-UpdateAvailable)) { return }
    if ($script:Changes -and $script:Changes.for -eq $script:VerLatest -and
        $script:Changes.from -eq $script:VerLocal) { return }
    if ($script:ChangesTask -and -not $script:ChangesTask.IsCompleted) { return }
    if (([datetime]::Now - $script:ChangesTry).TotalMinutes -lt 10) { return }
    $script:ChangesTry = Get-Date
    try {
        $wc = New-Object System.Net.WebClient
        $wc.Encoding = [System.Text.Encoding]::UTF8
        $script:ChangesTask = $wc.DownloadStringTaskAsync($ChangelogUrl)
    } catch {
        $script:ChangesTask = $null
    }
}

function Collect-ChangelogProbe {
    if (-not $script:ChangesTask -or -not $script:ChangesTask.IsCompleted) { return }
    $t = $script:ChangesTask
    $script:ChangesTask = $null
    if ($t.Status -ne 'RanToCompletion') { return }

    $from  = [version]$script:VerLocal
    $to    = [version]$script:VerLatest
    $items = @()
    foreach ($chunk in ([string]$t.Result -split '(?m)^## ')) {
        $m = [regex]::Match($chunk, '^(\d+\.\d+\.\d+)')
        if (-not $m.Success) { continue }
        $v = [version]$m.Groups[1].Value
        if ($v -le $from -or $v -gt $to) { continue }
        foreach ($line in ($chunk -split '\r?\n')) {
            if ($line -match '^\s*[-*]\s+(.+)$') { $items += ($Matches[1] -replace '`', '') }
        }
    }
    $script:Changes = @{ for = $script:VerLatest; from = $script:VerLocal; items = $items }
}

function New-ChangesTooltip {
    $tb = New-Object System.Windows.Controls.TextBlock
    $tb.MaxWidth     = 460
    $tb.TextWrapping = 'Wrap'
    $tb.FontFamily   = 'Segoe UI'
    $tb.FontSize     = 11
    $head  = (T 'chg.head') -f $script:VerLocal, $script:VerLatest
    $click = T 'chg.click'
    if (-not $script:Changes -or $script:Changes.for -ne $script:VerLatest) {
        $tb.Text = "$head`n`n$(T 'chg.loading')`n`n$click"
        return $tb
    }
    $items = $script:Changes.items
    $max   = 25
    $lines = @($items | Select-Object -First $max | ForEach-Object { "• $_" })
    if ($items.Count -gt $max) { $lines += (T 'chg.more') -f ($items.Count - $max) }
    if (-not $items.Count)     { $lines += T 'chg.empty' }
    $tb.Text = "$head`n`n$($lines -join "`n")`n`n$click"
    return $tb
}

# Both changelogs open on GitHub on a click on the version; the tooltip over the
# widget's version reads its CHANGELOG.md next to the script.
$ChangelogPage   = 'https://github.com/anthropics/claude-code/blob/main/CHANGELOG.md'
$ClawdChangelog  = Join-Path $script:Root 'CHANGELOG.md'
$ClawdChangelogPage = 'https://github.com/Enhed/clawd-usage-winwidget/blob/main/CHANGELOG.md'

function Open-ClawdChangelog { Start-Process $ClawdChangelogPage }

# The current version's section of CHANGELOG.md - for the tooltip.
function New-ClawdChangesTooltip {
    $tb = New-Object System.Windows.Controls.TextBlock
    $tb.MaxWidth     = 460
    $tb.TextWrapping = 'Wrap'
    $tb.FontFamily   = 'Segoe UI'
    $tb.FontSize     = 11
    $items = @()
    try {
        $text = [System.IO.File]::ReadAllText($ClawdChangelog, [System.Text.Encoding]::UTF8)
        $m = [regex]::Match($text, "(?ms)^## $([regex]::Escape($WidgetVersion))\s*`$(.*?)(?=^## |\z)")
        if ($m.Success) {
            # Bullets may wrap over several lines - glue them back, drop markdown marks.
            foreach ($b in ($m.Groups[1].Value -split '(?m)^- ')) {
                $b = ($b -replace '\s+', ' ').Trim() -replace '\*\*', '' -replace '`', ''
                if ($b) { $items += "• $b" }
            }
        }
    } catch {}
    $tb.Text = "$((T 'chg.clawdHead') -f $WidgetVersion)`n`n$($items -join "`n")`n`n$(T 'chg.clawdClick')"
    return $tb
}

# ------------------------------------------------ the widget's own release ----
# The latest release of the widget itself, from GitHub, checked together with
# Claude Code's version. A new one: the version line in the corner turns yellow,
# a Windows notification once per version, a click updates the files and restarts.

$ReleaseApi = 'https://api.github.com/repos/Enhed/clawd-usage-winwidget/releases/latest'
$UpdateStatePath = Join-Path $script:Root 'update-state.json'

# A click on the update leaves a mark in TEMP, outside the widget's folder - that
# folder may turn out not writable (Program Files, Windows' controlled folder access),
# and then the update cannot put its files there either. Back with the version the
# mark names still ahead: the update did not happen. That is remembered (in memory
# too, when update-state.json cannot be written), so the next click opens the release
# page instead of going round in the same loop.
$UpdateMarkPath = Join-Path ([System.IO.Path]::GetTempPath()) 'clawd-update-attempt.json'
$script:UpdateMem = @{}
try {
    $mark = [System.IO.File]::ReadAllText($UpdateMarkPath) | ConvertFrom-Json
    Remove-Item -LiteralPath $UpdateMarkPath -Force -ErrorAction SilentlyContinue
    if ([version][string]$mark.ver -gt [version]$WidgetVersion) {
        $script:UpdateMem = @{ failed = [string]$mark.ver; failedTold = $false }
    }
} catch {}

$script:ClawdRel     = $null   # @{ ver; url; zip; notes = @() }
$script:ClawdRelTask = $null
$script:ClawdDl      = $null   # @{ task; zip; dir } - an update being downloaded

function Start-ReleaseProbe {
    if ($script:ClawdRelTask -and -not $script:ClawdRelTask.IsCompleted) { return }
    try {
        $wc = New-Object System.Net.WebClient
        $wc.Encoding = [System.Text.Encoding]::UTF8
        # GitHub's API turns away requests without a User-Agent.
        $wc.Headers.Add('User-Agent', 'clawd-usage-winwidget')
        $script:ClawdRelTask = $wc.DownloadStringTaskAsync($ReleaseApi)
    } catch {
        $script:ClawdRelTask = $null
    }
}

function Collect-ReleaseProbe {
    if (-not $script:ClawdRelTask -or -not $script:ClawdRelTask.IsCompleted) { return }
    $t = $script:ClawdRelTask
    $script:ClawdRelTask = $null
    if ($t.Status -ne 'RanToCompletion') { return }
    try { $j = [string]$t.Result | ConvertFrom-Json } catch { return }
    $m = [regex]::Match([string]$j.tag_name, '(\d+\.\d+\.\d+)')
    if (-not $m.Success) { return }
    # Bullets may wrap over several lines - glue them back, drop markdown marks
    # and pictures (a release may show screenshots under its list).
    $notes = @()
    $body = [string]$j.body -replace '!\[[^\]]*\]\([^)]*\)', '' -replace '<img[^>]*>', ''
    foreach ($b in ($body -split '(?m)^- ')) {
        $b = ($b -replace '\s+', ' ').Trim() -replace '\*\*', '' -replace '`', ''
        if ($b -and $b -notmatch '^To install:') { $notes += "• $b" }
    }
    $script:ClawdRel = @{ ver = $m.Groups[1].Value; url = [string]$j.html_url; zip = [string]$j.zipball_url; notes = $notes }
    if (Test-ClawdUpdate) { Send-ClawdUpdateNotice }
}

function Test-ClawdUpdate {
    if (-not $script:ClawdRel) { return $false }
    try { return ([version]$script:ClawdRel.ver -gt [version]$WidgetVersion) } catch { return $false }
}

# update-state.json: notified - the version already announced; failed - a version
# self-update.ps1 had to roll back, failedTold - whether the user heard about that.
function Get-UpdateState {
    $st = @{}
    try {
        $j = [System.IO.File]::ReadAllText($UpdateStatePath) | ConvertFrom-Json
        foreach ($p in $j.PSObject.Properties) { $st[$p.Name] = $p.Value }
    } catch {}
    foreach ($k in $script:UpdateMem.Keys) { $st[$k] = $script:UpdateMem[$k] }
    return $st
}

# Not writable - kept in memory for this run, so a notice is still said once.
function Save-UpdateState($st) {
    try { ConvertTo-Json $st | Out-File $UpdateStatePath -Encoding utf8; $script:UpdateMem = @{} }
    catch { $script:UpdateMem = @{} + $st }
}

# A Windows notification once per new version, even across restarts; and once
# about a rolled back one.
function Send-ClawdUpdateNotice {
    $ver = $script:ClawdRel.ver
    $st = Get-UpdateState
    if ($st.failed -eq $ver) {
        if (-not $st.failedTold) {
            $st.failedTold = $true
            Save-UpdateState $st
            $notify.ShowBalloonTip(15000, 'Clawd', ((T 'clawd.rolledBack') -f $ver, $WidgetVersion),
                                   [System.Windows.Forms.ToolTipIcon]::Warning)
        }
        return
    }
    if ($st.notified -eq $ver) { return }
    $st.notified = $ver
    Save-UpdateState $st
    $notify.ShowBalloonTip(15000, ((T 'clawd.notifyTitle') -f $ver), ((T 'clawd.notifyText') -f $ver),
                           [System.Windows.Forms.ToolTipIcon]::Info)
}

# A version that did not start once is not installed by a click again - the release page opens.
function Test-ClawdUpdateFailed { return ($script:ClawdRel -and (Get-UpdateState).failed -eq $script:ClawdRel.ver) }

function New-ClawdUpdateTooltip {
    $tb = New-Object System.Windows.Controls.TextBlock
    $tb.MaxWidth     = 460
    $tb.TextWrapping = 'Wrap'
    $tb.FontFamily   = 'Segoe UI'
    $tb.FontSize     = 11
    $max   = 25
    $lines = @($script:ClawdRel.notes | Select-Object -First $max)
    if ($script:ClawdRel.notes.Count -gt $max) { $lines += (T 'chg.more') -f ($script:ClawdRel.notes.Count - $max) }
    $click = $(if (Test-ClawdGitCopy) { T 'clawd.clickGit' } elseif (Test-ClawdUpdateFailed) { T 'clawd.clickFailed' } else { T 'clawd.click' })
    $tb.Text = "$((T 'clawd.tipHead') -f $WidgetVersion, $script:ClawdRel.ver)`n`n$($lines -join "`n")`n`n$click"
    return $tb
}

# A git clone is the developer's working copy: files are not overwritten there.
function Test-ClawdGitCopy { return (Test-Path (Join-Path $script:Root '.git')) }

# Click on the version: download the release, unpack it next to the old files, then
# a helper waits for this process to end, copies the files over and starts the
# widget again. Local files (config.json, chat-state.json...) are not in the release.
function Start-ClawdUpdate {
    if (-not (Test-ClawdUpdate) -or $script:ClawdDl) { return }
    # A git clone is updated with git: the click shows what changed.
    if (Test-ClawdGitCopy) { Open-ClawdChangelog; return }
    if (Test-ClawdUpdateFailed) { Start-Process $script:ClawdRel.url; return }
    try {
        $zip = Join-Path $env:TEMP "cuw-update-$PID.zip"
        $wc = New-Object System.Net.WebClient
        $wc.Headers.Add('User-Agent', 'clawd-usage-winwidget')
        $script:ClawdDl = @{ task = $wc.DownloadFileTaskAsync($script:ClawdRel.zip, $zip); zip = $zip
                             dir = Join-Path $env:TEMP "cuw-update-$PID" }
    } catch {
        $script:ClawdDl = $null
        $notify.ShowBalloonTip(10000, 'Clawd', ((T 'clawd.failed') -f $_.Exception.Message), [System.Windows.Forms.ToolTipIcon]::Warning)
    }
}

function Collect-ClawdUpdate {
    $d = $script:ClawdDl
    if (-not $d -or -not $d.task.IsCompleted) { return }
    $script:ClawdDl = $null
    try {
        if ($d.task.Status -ne 'RanToCompletion') { throw $d.task.Exception.InnerException }
        if (Test-Path $d.dir) { Remove-Item $d.dir -Recurse -Force }
        Expand-Archive -LiteralPath $d.zip -DestinationPath $d.dir -Force
        # GitHub's archive has everything in one top folder.
        $src = Get-ChildItem $d.dir -Directory | Select-Object -First 1
        if (-not $src -or -not (Test-Path (Join-Path $src.FullName 'widget.ps1'))) { throw 'no widget.ps1 in the archive' }
    } catch {
        $notify.ShowBalloonTip(10000, 'Clawd', ((T 'clawd.failed') -f $_), [System.Windows.Forms.ToolTipIcon]::Warning)
        return
    }
    # The rest - waiting for this process to end, the copy, the start and a rollback
    # if the new version does not come up - is self-update.ps1's job.
    try { ConvertTo-Json @{ ver = $script:ClawdRel.ver } | Out-File $UpdateMarkPath -Encoding utf8 } catch {}
    $q = { param($s) '"' + $s + '"' }
    $argv = @('-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass',
              '-File', (& $q (Join-Path $script:Root 'self-update.ps1')),
              '-WaitPid', $PID, '-Source', (& $q $src.FullName), '-Root', (& $q $script:Root),
              '-Version', $script:ClawdRel.ver, '-Zip', (& $q $d.zip), '-Dir', (& $q $d.dir))
    Start-Process -FilePath (Join-Path $PSHOME 'powershell.exe') -WindowStyle Hidden -ArgumentList $argv
    Stop-Widget
}

function Start-ClaudeUpdate {
    if ($script:UpdateProc -and -not $script:UpdateProc.HasExited) { return }
    # Visible window: let the user see the update progress and how it ended.
    $script:UpdateProc = Start-Process -FilePath 'cmd.exe' `
        -ArgumentList '/c', "`"`"$($script:ClaudeExe)`" update & pause`"" -PassThru
}
