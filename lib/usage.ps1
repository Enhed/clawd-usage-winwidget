# ------------------------------------------------- official percentages ----
# `claude -p "/usage"` returns the same numbers as interactive /usage: limit
# percentages from the server for the current auth. No model call, no tokens
# spent. A call takes ~2 s, so it runs asynchronously and rarely.

$script:ClaudeExe = $null
try { $script:ClaudeExe = (Get-Command claude -ErrorAction Stop).Source } catch {
    [System.Windows.MessageBox]::Show(
        (T 'err.noClaude'),
        'clawd-usage-winwidget', 'OK', 'Error') | Out-Null
    exit 1
}

$script:UsageProc = $null
$script:UsageFile = Join-Path $env:TEMP "cuw-usage-$PID.txt"
$script:Usage     = $null
$script:UsageAt   = [datetime]::MinValue

$script:UsageTry  = [datetime]::MinValue

function Start-UsageProbe {
    if ($script:UsageProc -and -not $script:UsageProc.HasExited) { return }
    $script:UsageTry = Get-Date
    try {
        $script:UsageProc = Start-Process -FilePath $script:ClaudeExe `
            -ArgumentList '-p','/usage','--output-format','text' `
            -RedirectStandardOutput $script:UsageFile -NoNewWindow -PassThru
    } catch {
        $script:UsageProc = $null
    }
}

function Parse-ResetStamp([string]$s) {
    # "Sep 16, 7:30am (Europe/Moscow)" or "Sep 21, 6am" -> DateTime in local time
    $m = [regex]::Match($s, '([A-Za-z]{3})\s+(\d{1,2}),\s*(\d{1,2})(?::(\d{2}))?\s*([ap]m)')
    if (-not $m.Success) { return $null }
    try {
        $min = $m.Groups[4].Value
        if (-not $min) { $min = '00' }
        $stamp = '{0} {1} {2} {3}:{4} {5}' -f $m.Groups[1].Value, $m.Groups[2].Value,
                 (Get-Date).Year, $m.Groups[3].Value, $min, $m.Groups[5].Value.ToUpper()
        $dt = [datetime]::ParseExact($stamp, 'MMM d yyyy h:mm tt',
                  [System.Globalization.CultureInfo]::InvariantCulture)
        # Around New Year the date may land in the past - then it is next year.
        if ($dt -lt (Get-Date).AddDays(-30)) { $dt = $dt.AddYears(1) }
        return $dt
    } catch { return $null }
}

# Stats block lines are shortened; unknown ones are kept as is, so new
# metrics from /usage are not lost. Translated on display - language changes on the fly.
$StatRules = @(
    @{ re = '^(\d+)% of your usage was at >(\S+) context';                   key = 'stat.bigCtx' }
    @{ re = '^(\d+)% of your usage went to always-on context over (\S+)';    key = 'stat.alwaysOn' }
    @{ re = '^(\d+)% of your usage came from subagent-heavy';                key = 'stat.subagents' }
    @{ re = '^(\d+)% of your usage came from sessions active for (\d+)\+? hours'; key = 'stat.long' }
    @{ re = '^Top MCP servers:\s*(.+)$';                                     key = 'stat.mcp' }
    @{ re = '^Top skills:\s*(.+)$';                                          key = 'stat.skills' }
    @{ re = '^Top subagents:\s*(.+)$';                                       key = 'stat.agents' }
)

function Format-StatLine([string]$line) {
    foreach ($r in $StatRules) {
        $x = [regex]::Match($line, $r.re)
        if ($x.Success) {
            $a = @(); for ($i = 1; $i -lt $x.Groups.Count; $i++) { $a += $x.Groups[$i].Value }
            return ((T $r.key) -f $a)
        }
    }
    return $line
}

function Parse-Period([string]$text, [string]$label) {
    # The "Last 24h · 298 requests · 12 sessions" block and the indented lines below it.
    $m = [regex]::Match($text, "(?m)^$label[^\r\n]*?(\d+)\s+requests[^\r\n]*?(\d+)\s+sessions[^\r\n]*\r?\n((?:[ \t]+[^\r\n]*\r?\n?)*)")
    if (-not $m.Success) { return $null }
    $lines = @()
    foreach ($raw in ($m.Groups[3].Value -split '\r?\n')) {
        $line = $raw.Trim()
        if ($line) { $lines += $line }
    }
    return @{ requests = [int]$m.Groups[1].Value; sessions = [int]$m.Groups[2].Value; lines = $lines }
}

function Collect-UsageProbe {
    if (-not $script:UsageProc -or -not $script:UsageProc.HasExited) { return }
    $script:UsageProc = $null
    if (-not (Test-Path $script:UsageFile)) { return }
    try {
        $text = [System.IO.File]::ReadAllText($script:UsageFile, [System.Text.Encoding]::UTF8)
    } catch { return }

    $u = @{
        session = $null; week = $null; fable = $null
        sessionReset = $null; weekReset = $null; fableReset = $null
        day = $null; week7 = $null
    }

    $m = [regex]::Match($text, 'Current session:\s*(\d+)%[^\r\n]*?resets\s*([^\r\n]+)')
    if ($m.Success) {
        $u.session      = [int]$m.Groups[1].Value
        $u.sessionReset = Parse-ResetStamp $m.Groups[2].Value
    }
    $m = [regex]::Match($text, 'Current week \(all models\):\s*(\d+)%[^\r\n]*?resets\s*([^\r\n]+)')
    if ($m.Success) {
        $u.week      = [int]$m.Groups[1].Value
        $u.weekReset = Parse-ResetStamp $m.Groups[2].Value
    }
    $m = [regex]::Match($text, 'Current week \(Fable\):\s*(\d+)%(?:[^\r\n]*?resets\s*([^\r\n]+))?')
    if ($m.Success) {
        $u.fable      = [int]$m.Groups[1].Value
        $u.fableReset = Parse-ResetStamp $m.Groups[2].Value
    }

    $u.day   = Parse-Period $text 'Last 24h'
    $u.week7 = Parse-Period $text 'Last 7d'

    if ($null -ne $u.session -or $null -ne $u.week) {
        $script:Usage   = $u
        $script:UsageAt = Get-Date
    }
}
