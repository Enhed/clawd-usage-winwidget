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
    language               = 'en'   # UI language: en or ru
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
        [PSCustomObject]$cfg | ConvertTo-Json -Depth 3 | Out-File $script:ConfigPath -Encoding utf8
    } catch {
        Write-Warning "could not save config.json: $($_.Exception.Message)"
    }
}

$script:Cfg = Load-Config
