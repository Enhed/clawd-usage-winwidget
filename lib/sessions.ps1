# ----------------------------------------------------------- sessions ----
# Claude Code keeps its own registry of running sessions: ~/.claude/sessions/<pid>.json,
# with name, folder and busy/idle status. A file can outlive its process, so
# check the process is alive and is the same process (procStart - start FILETIME).

$SessionsDir = Join-Path $env:USERPROFILE '.claude\sessions'

function Get-Sessions {
    $own = @()
    foreach ($p in @($script:UsageProc, $script:AuthProc)) { if ($p) { $own += $p.Id } }
    if ($script:ChatProc) { $own += $script:ChatProc.proc.Id }
    $list = @()
    foreach ($f in @(Get-ChildItem $SessionsDir -Filter *.json -ErrorAction SilentlyContinue)) {
        try { $j = [System.IO.File]::ReadAllText($f.FullName, [System.Text.Encoding]::UTF8) | ConvertFrom-Json } catch { continue }
        if (-not $j.pid -or $own -contains $j.pid) { continue }
        $proc = Get-Process -Id $j.pid -ErrorAction SilentlyContinue
        if (-not $proc) { continue }
        try {
            if ($j.procStart -and
                [math]::Abs($proc.StartTime.ToFileTimeUtc() - [int64]$j.procStart) -gt 50000000) { continue }
        } catch {}
        $name = [string]$j.name
        if (-not $name -and $j.cwd) { $name = Split-Path -Leaf $j.cwd }
        # waiting - the session waits for the user: permission, question, dialog (see waitingFor).
        $list += @{ name = $name; cwd = [string]$j.cwd; busy = ($j.status -eq 'busy')
                    waiting = ($j.status -eq 'waiting'); waitingFor = [string]$j.waitingFor
                    kind = [string]$j.kind; sessionId = [string]$j.sessionId; pid = [int]$j.pid }
    }
    return ,$list
}

# Sessions published by other machines (remoteSessions in config.json): URLs or file
# paths, each returning { generatedAt, host, sessions = [ <session json> ] }, already
# filtered to live sessions by the publisher, so there is no process check here.
# Each source is fetched in the background; a failed, hung or stale source simply
# contributes no sessions.

$RemoteStaleSeconds = 120   # a feed (or our last good fetch of it) older than this is ignored
$RemoteHungSeconds  = 30    # a fetch still running after this is cancelled

$script:Remote = @{}        # source -> @{ wc; task; try; at; list }

function ConvertTo-RemoteSessions($text) {
    $j = $text | ConvertFrom-Json
    if ($j.generatedAt) {
        $age = ([datetimeoffset]::UtcNow - [datetimeoffset]::Parse([string]$j.generatedAt)).TotalSeconds
        if ($age -gt $RemoteStaleSeconds) { return ,@() }
    }
    $host_ = [string]$j.host
    $items = $(if ($null -ne $j.sessions) { $j.sessions } else { $j })
    $list = @()
    foreach ($s in @($items)) {
        if (-not $s -or $s -is [string]) { continue }
        $name = [string]$s.name
        if (-not $name -and $s.cwd) { $name = Split-Path -Leaf ([string]$s.cwd) }
        if (-not $name -and $s.sessionId) { $name = ([string]$s.sessionId).Substring(0, [math]::Min(8, ([string]$s.sessionId).Length)) }
        $list += @{ name = $name; cwd = [string]$s.cwd; busy = ($s.status -eq 'busy')
                    waiting = ($s.status -eq 'waiting'); waitingFor = [string]$s.waitingFor
                    kind = [string]$s.kind; sessionId = [string]$s.sessionId; pid = 0; host = $host_ }
    }
    return ,$list
}

# Collects finished fetches, starts the due ones and returns the sessions from all
# sources that answered recently. $local - the local sessions, to drop duplicates.
function Get-RemoteSessions($local) {
    $sources = @($script:Cfg.remoteSessions | Where-Object { $_ } | ForEach-Object { [string]$_ })
    foreach ($k in @($script:Remote.Keys)) {
        if ($sources -notcontains $k) {
            try { $script:Remote[$k].wc.CancelAsync() } catch {}
            $script:Remote.Remove($k)
        }
    }
    $now = Get-Date
    $out = @()
    foreach ($src in $sources) {
        $r = $script:Remote[$src]
        if (-not $r) { $r = @{ wc = $null; task = $null; try = [datetime]::MinValue; at = [datetime]::MinValue; list = @() }; $script:Remote[$src] = $r }
        if ($r.task -and $r.task.IsCompleted) {
            if ($r.task.Status -eq 'RanToCompletion') {
                try { $r.list = ConvertTo-RemoteSessions $r.task.Result; $r.at = $now } catch { $r.list = @() }
            } else { $r.list = @() }
            $r.task = $null
        } elseif ($r.task -and ($now - $r.try).TotalSeconds -gt $RemoteHungSeconds) {
            try { $r.wc.CancelAsync() } catch {}
            $r.task = $null
        }
        if (-not $r.task -and ($now - $r.try).TotalSeconds -ge [double]$script:Cfg.refreshSeconds - 1) {
            $r.try = $now
            try {
                # WebClient reads file paths too (as file:// URIs), so both go the same way.
                $uri = $(if ($src -match '^[a-z][a-z0-9+.-]+://') { New-Object Uri $src }
                         else { New-Object Uri ([System.IO.Path]::GetFullPath([Environment]::ExpandEnvironmentVariables($src))) })
                $wc = New-Object System.Net.WebClient
                $wc.Encoding = [System.Text.Encoding]::UTF8
                $wc.Headers['Cache-Control'] = 'no-cache'
                $r.wc = $wc
                $r.task = $wc.DownloadStringTaskAsync($uri)
            } catch { $r.task = $null }
        }
        if (($now - $r.at).TotalSeconds -le $RemoteStaleSeconds) { $out += $r.list }
    }
    $ids = @($local | ForEach-Object { $_.sessionId } | Where-Object { $_ })
    return ,@($out | Where-Object { -not $_.sessionId -or $ids -notcontains $_.sessionId })
}
