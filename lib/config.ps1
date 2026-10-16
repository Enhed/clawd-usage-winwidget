# ---------------------------------------------------------------- config ----

$DefaultConfig = [ordered]@{
    refreshSeconds         = 10
    usageIntervalSeconds   = 60     # how often to fetch official percentages
    versionIntervalSeconds = 3600   # how often to check for a Claude Code update
    expanded               = $false # whether the details block is expanded
    scale                  = 1.35   # scale of the whole window
    warnPercent            = 60
    critPercent            = 85
    opacity                = 1.0
    topmost                = $false # keep the window above all others
    trayResetClock         = $false # tray tooltip: resets as clock times (03:20, tmrw 01:00) instead of a countdown
    showStats              = $true  # "last 24h" / "last 7 days" blocks in details
    showStatus             = $true  # Anthropic service status line
    statusIntervalSeconds  = 120    # how often to query status.claude.com
    showSessions           = $true  # running Claude Code sessions
    showAccount            = $true  # account plan and email at the bottom of the window
    accountIntervalSeconds = 600    # how often to run `claude auth status`
    showMascot             = $true  # animated Clawd above the session bar
    showSky                = $true  # sky behind the mascot: time of day and weather from Open-Meteo
    weatherIntervalSeconds = 900    # how often to fetch the weather
    weatherLat             = $null  # coordinates; empty - detect by IP
    weatherLon             = $null
    showAdvisor            = $true  # Clawd's tips about the computer: disk space, autostart, unused apps
    advisorIntervalMinutes = 30     # how often to look the computer over
    advisorDiskGB          = 10     # warn when a drive has less free space, GB
    advisorJunkGB          = 5      # mention temp folders, caches and Downloads when they add up to this, GB
    advisorUnusedDays      = 90     # an app not started this long counts as unused
    advisorUptimeDays      = 7      # suggest a restart after this many days
    advisorMemPercent      = 40     # a program using this share of memory is worth a word
    showChat               = $true  # chat with Clawd in the panel (uses your plan's limits)
    chatModel              = 'sonnet' # model for the chat
    chatTimeoutSeconds     = 300    # a reply taking longer is cancelled
    chatAutoRun            = $false # run Clawd's scripts at once, without the "Run" click (toggle in the panel)
    quickModel             = 'haiku' # model for small jobs: an unclear reminder time, recurring tasks by default
    showTasks              = $true  # recurring tasks from the tasks folder in Clawd's home
    tasksMaxPercent        = 80     # tasks wait while the session or the week is at this percent or more (100 - never)
    language               = 'en'   # UI language: en, ru or fr
    runAsAdmin             = $false # run the widget elevated (UAC prompt at start)
    clawdHome              = $null  # Clawd's folder: chat, reminders, tips.md, his session; empty - ~\Clawd
    clawdSession           = $false # keep Clawd's own Claude Code session running there, with Remote Control
    clawdSessionName       = 'clawd-usage-winwidget' # its name in Remote Control and the session list
    clawdSessionAdmin      = $false # run that session as administrator
    clawdSessionHidden     = $true  # without a window: talk to it from the phone or claude.ai
    left                   = $null
    top                    = $null
}

function Load-Config {
    $cfg = [ordered]@{}
    foreach ($k in $DefaultConfig.Keys) { $cfg[$k] = $DefaultConfig[$k] }
    if (Test-Path $script:ConfigPath) {
        try {
            $raw = Get-Content $script:ConfigPath -Raw -Encoding UTF8 | ConvertFrom-Json
            foreach ($p in $raw.PSObject.Properties) {
                if ($cfg.Contains($p.Name)) { $cfg[$p.Name] = $p.Value }
            }
        } catch {
            Write-Warning "config.json is unreadable, using defaults: $($_.Exception.Message)"
        }
    }
    return $cfg
}

function Save-Config($cfg) {
    try {
        # Keys this version does not know stay in the file: written by a newer
        # version, or by hand while an older copy was still running - saving the
        # window position must not quietly drop them.
        $out = [ordered]@{}
        if (Test-Path $script:ConfigPath) {
            try {
                $raw = Get-Content $script:ConfigPath -Raw -Encoding UTF8 | ConvertFrom-Json
                foreach ($p in $raw.PSObject.Properties) { $out[$p.Name] = $p.Value }
            } catch {}
        }
        foreach ($k in $cfg.Keys) { $out[$k] = $cfg[$k] }
        [PSCustomObject]$out | ConvertTo-Json -Depth 3 | Out-File $script:ConfigPath -Encoding utf8
    } catch {
        Write-Warning "could not save config.json: $($_.Exception.Message)"
    }
}

$script:Cfg = Load-Config

# Clawd's home: the chat works there, reminders and tips.md live there, and so does
# his own session. Created on first use.
function Get-ClawdHome {
    $d = [string]$script:Cfg.clawdHome
    if (-not $d) { $d = Join-Path $env:USERPROFILE 'Clawd' }
    $d = [Environment]::ExpandEnvironmentVariables($d).TrimEnd('\')
    if (-not [System.IO.Directory]::Exists($d)) { try { [void][System.IO.Directory]::CreateDirectory($d) } catch {} }
    return $d
}
