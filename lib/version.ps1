# --------------------------------------------------- version and update ----
# The latest release number comes from the same place the official installer uses
# (https://claude.ai/install.ps1): downloads.claude.ai/claude-code-releases/<channel>.
# Channel - autoUpdatesChannel from ~/.claude/settings.json, latest by default.

[System.Net.ServicePointManager]::SecurityProtocol =
    [System.Net.ServicePointManager]::SecurityProtocol -bor [System.Net.SecurityProtocolType]::Tls12

$script:VerLocal  = $null
$script:VerLatest = $null
$script:VerTask   = $null
$script:VerAt     = [datetime]::MinValue

function Get-UpdateChannel {
    try {
        $s = Get-Content (Join-Path $env:USERPROFILE '.claude\settings.json') -Raw -Encoding UTF8 | ConvertFrom-Json
        if ($s.autoUpdatesChannel -in @('stable','latest')) { return $s.autoUpdatesChannel }
    } catch {}
    return 'latest'
}

function Start-VersionProbe {
    if ($script:VerTask -and -not $script:VerTask.IsCompleted) { return }
    $script:VerAt = Get-Date
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

function Start-ClaudeUpdate {
    if ($script:UpdateProc -and -not $script:UpdateProc.HasExited) { return }
    # Visible window: let the user see the update progress and how it ended.
    $script:UpdateProc = Start-Process -FilePath 'cmd.exe' `
        -ArgumentList '/c', "`"`"$($script:ClaudeExe)`" update & pause`"" -PassThru
}
