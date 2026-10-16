# ------------------------------------------------------- service status ----
# The official Statuspage status page: summary.json returns the overall indicator,
# component states (claude.ai, API, Claude Code...) and active incidents.

$StatusUrl = 'https://status.claude.com'

$script:Status     = $null   # @{ indicator; incidents; broken = @(@{ name; state }) }
$script:StatusTask = $null
$script:StatusTry  = [datetime]::MinValue
$script:StatusAt   = [datetime]::MinValue

function Start-StatusProbe {
    if ($script:StatusTask -and -not $script:StatusTask.IsCompleted) { return }
    $script:StatusTry = Get-Date
    try {
        $wc = New-Object System.Net.WebClient
        $wc.Encoding = [System.Text.Encoding]::UTF8
        $script:StatusTask = $wc.DownloadStringTaskAsync("$StatusUrl/api/v2/summary.json")
    } catch {
        $script:StatusTask = $null
    }
}

function Collect-StatusProbe {
    if (-not $script:StatusTask -or -not $script:StatusTask.IsCompleted) { return }
    $t = $script:StatusTask
    $script:StatusTask = $null
    if ($t.Status -ne 'RanToCompletion') { return }
    try { $j = $t.Result | ConvertFrom-Json } catch { return }

    $broken = @()
    foreach ($c in $j.components) {
        if ($c.group -or $c.status -eq 'operational') { continue }
        # "Claude API (api.anthropic.com)" -> "Claude API"
        $broken += @{ name = ($c.name -replace '\s*\(.*\)\s*$', ''); state = [string]$c.status }
    }
    $script:Status = @{
        indicator = [string]$j.status.indicator
        incidents = @($j.incidents | ForEach-Object { $_.name })
        broken    = $broken
    }
    $script:StatusAt = Get-Date
}
