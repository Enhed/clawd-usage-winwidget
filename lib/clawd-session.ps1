# --------------------------------------------------------- clawd session ----
# Optional (clawdSession): Clawd's own interactive Claude Code session in his home
# folder, with Remote Control under the widget's name (clawdSessionName) - to talk
# to him from the phone or claude.ai. The widget keeps it running: started with
# the widget, started again if it is gone. It comes back to its own conversation
# (--resume with the id remembered here, not --continue: the panel's chat
# conversations live in the same folder).
# What Clawd knows about the widget is in clawd-session-prompt.md.

$ClawdStatePath     = Join-Path $script:Root 'clawd-state.json'
$SessionPromptPath  = Join-Path $script:Root 'clawd-session-prompt.md'
$script:ClawdLaunch = [datetime]::MinValue
$script:ClawdMisses = 0     # launches after which no session showed up

function Get-ClawdSessionName {
    $n = [string]$script:Cfg.clawdSessionName
    if (-not $n.Trim()) { $n = 'clawd-usage-winwidget' }
    return $n.Trim()
}

function Get-ClawdSessionId {
    try { return [string](([System.IO.File]::ReadAllText($ClawdStatePath) | ConvertFrom-Json).sessionId) } catch { return '' }
}

function Set-ClawdSessionId([string]$id) {
    if ($id -eq (Get-ClawdSessionId)) { return }
    try { ConvertTo-Json @{ sessionId = $id } | Out-File $ClawdStatePath -Encoding utf8 } catch {}
}

# In a folder not trusted yet Claude Code asks about it in the terminal -
# a hidden window would wait for that answer forever.
function Test-FolderTrusted([string]$dir) {
    try {
        $j = [System.IO.File]::ReadAllText((Get-ClaudeGlobalConfigPath)) | ConvertFrom-Json
        $p = $j.projects.PSObject.Properties | Where-Object { $_.Name.Replace('/', '\').TrimEnd('\') -eq $dir } | Select-Object -First 1
        return [bool]($p -and $p.Value.hasTrustDialogAccepted)
    } catch { return $false }
}

function Start-ClawdSession {
    $dir = Get-ClawdHome
    $q = { param($s) "'" + ($s -replace "'", "''") + "'" }
    $name = & $q (Get-ClawdSessionName)
    $cli = @('-n', $name)
    # Its own conversation if there is one (conversations live in
    # projects\<path with every non-alphanumeric as -> in Claude Code's folder), a new one otherwise.
    $id = Get-ClawdSessionId
    $key = [regex]::Replace($dir, '[^A-Za-z0-9]', '-')
    if ($id -and (Test-Path -LiteralPath ([System.IO.Path]::Combine((Get-ClaudeConfigDir), "projects\$key\$id.jsonl")))) {
        $cli += @('--resume', $id)
    }
    $cli += @('--remote-control', $name, '--append-system-prompt-file', (& $q $SessionPromptPath))

    $hidden = $script:Cfg.clawdSessionHidden -and (Test-FolderTrusted $dir)
    $cmd = "Set-Location -LiteralPath $(& $q $dir); & $(& $q $script:ClaudeExe) $($cli -join ' ')"
    if (-not $hidden) {
        # A visible window stays open (-NoExit) with the exit code, so a failed start can be read.
        $cmd += "; Write-Host `"claude exited with code `$LASTEXITCODE`""
    }
    $enc = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($cmd))
    $shell = Join-Path $PSHOME 'powershell.exe'

    if ($hidden) {
        $exe = $shell
        $argv = @('-NoProfile', '-WindowStyle', 'Hidden', '-EncodedCommand', $enc)
    } else {
        # Windows Terminal when it is installed, a plain console otherwise.
        $exe = $shell
        $argv = @('-NoExit', '-EncodedCommand', $enc)
        $wt = Get-Command wt.exe -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($wt) {
            $exe = $wt.Source
            $argv = @('new-tab', $shell) + $argv
        }
    }
    $style = $(if ($hidden) { 'Hidden' } else { 'Normal' })

    if ($script:Cfg.clawdSessionAdmin -and -not $script:IsAdmin) {
        # Elevation blocks the caller until UAC is answered - leave that to a hidden
        # helper so the window does not freeze. -WorkingDirectory is ignored by RunAs,
        # hence Set-Location inside the command.
        $outer = "Start-Process -FilePath $(& $q $exe) -Verb RunAs -WindowStyle $style -ArgumentList $(($argv | ForEach-Object { & $q $_ }) -join ',')"
        $enc2 = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($outer))
        Start-Process -FilePath $shell -WindowStyle Hidden -ArgumentList '-NoProfile', '-EncodedCommand', $enc2
    } else {
        # The widget's own rights are passed on: elevated widget - elevated session.
        Start-Process -FilePath $exe -WindowStyle $style -ArgumentList $argv
    }
}

# Stops Clawd's session (with its child processes); the next tick starts it again
# with the current clawd-session-prompt.md, back in the same conversation.
function Restart-ClawdSession {
    $dir = Get-ClawdHome
    foreach ($s in (Get-Sessions)) {
        if ($s.name -eq (Get-ClawdSessionName) -and $s.cwd -and $s.cwd.TrimEnd('\') -eq $dir -and $s.pid) {
            & taskkill.exe /PID $s.pid /T /F 2>&1 | Out-Null
        }
    }
    $script:ClawdLaunch = [datetime]::MinValue
    $script:ClawdMisses = 0
}

# Every tick: a session in the home folder - remember Clawd's id; none - start one.
function Update-ClawdSession($ss) {
    if (-not $script:Cfg.clawdSession) { return }
    $dir = Get-ClawdHome
    $there = @($ss | Where-Object { $_.cwd -and $_.cwd.TrimEnd('\') -eq $dir -and $_.kind -eq 'interactive' })
    if ($there.Count) {
        $script:ClawdMisses = 0
        $mine = $there | Where-Object { $_.name -eq (Get-ClawdSessionName) } | Select-Object -First 1
        if ($mine -and $mine.sessionId) { Set-ClawdSessionId $mine.sessionId }
        return
    }
    # Just started - give it time to show up in the registry.
    if (([datetime]::Now - $script:ClawdLaunch).TotalMinutes -lt 3) { return }
    # Three starts in a row with nothing to show for it - stop trying until restart.
    if ($script:ClawdMisses -ge 3) { return }
    if ($script:ClawdLaunch -ne [datetime]::MinValue) {
        $script:ClawdMisses++
        if ($script:ClawdMisses -ge 3) {
            try {
                "$(Get-Date -Format s)`tclawd session: did not start three times, giving up until restart" |
                    Out-File (Join-Path $script:Root 'widget-error.log') -Append -Encoding utf8
            } catch {}
            return
        }
    }
    $script:ClawdLaunch = Get-Date
    try { Start-ClawdSession } catch {
        try {
            "$(Get-Date -Format s)`tclawd session: $($_.Exception.Message)" |
                Out-File (Join-Path $script:Root 'widget-error.log') -Append -Encoding utf8
        } catch {}
    }
}
