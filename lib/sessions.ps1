# ----------------------------------------------------------- sessions ----
# Claude Code keeps its own registry of running sessions: ~/.claude/sessions/<pid>.json,
# with name, folder and busy/idle status. A file can outlive its process, so
# check the process is alive and is the same process (procStart - start FILETIME).

$SessionsDir = Join-Path $env:USERPROFILE '.claude\sessions'

function Get-Sessions {
    $own = @()
    foreach ($p in @($script:UsageProc, $script:AuthProc)) { if ($p) { $own += $p.Id } }
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
                    waiting = ($j.status -eq 'waiting'); waitingFor = [string]$j.waitingFor }
    }
    return ,$list
}
