<#
  Pre-release check: run before every release. Each case runs a copy of the
  widget built from the working tree in a sandbox of its own - its own folder,
  its own TEMP, its own mutex (CUW_SMOKE) - so the widget you are running is not
  touched. Each copy shows a tray icon for a few seconds.

    start     the copy starts with junk left in TEMP (a non-empty cuw-* folder,
              the one that hung 1.4.0), reaches its first update and keeps
              running without errors in widget-error.log;
    update    self-update.ps1 replaces an older copy with the working tree and
              the new version comes up;
    rollback  self-update.ps1 installs a version that hangs at start, and the
              old one comes back with the failed version in update-state.json.

  powershell -ExecutionPolicy Bypass -File tools\smoke.ps1 [-Cases start,update]
  Exit code 0 - all passed.
#>
param([string[]]$Cases = @('start', 'update', 'rollback'))

$ErrorActionPreference = 'Stop'
$Repo  = Split-Path -Parent $PSScriptRoot
$Box   = Join-Path ([System.IO.Path]::GetTempPath()) "clawd-smoke-$PID"
$Shell = Join-Path $PSHOME 'powershell.exe'
$failed = 0

# What a release would contain: tracked files plus new ones not ignored.
function Copy-Tree([string]$to) {
    [void][System.IO.Directory]::CreateDirectory($to)
    foreach ($rel in @(& git -C $Repo ls-files --cached --others --exclude-standard)) {
        if (-not (Test-Path -LiteralPath (Join-Path $Repo $rel))) { continue }   # deleted, not committed yet
        $dst = Join-Path $to $rel
        [void][System.IO.Directory]::CreateDirectory((Split-Path -Parent $dst))
        Copy-Item -LiteralPath (Join-Path $Repo $rel) -Destination $dst -Force
    }
}

# A quiet config: no elevation, no Clawd session, no background tasks or scans.
function Set-SmokeConfig([string]$root) {
    $home_ = Join-Path $root 'home'
    @{ runAsAdmin = $false; clawdSession = $false; showTasks = $false; showAdvisor = $false
       showSky = $false; language = 'en'; clawdHome = $home_ } |
        ConvertTo-Json | Out-File (Join-Path $root 'config.json') -Encoding utf8
}

function Set-Version([string]$root, [string]$ver) {
    $p = Join-Path $root 'widget.ps1'
    $s = [System.IO.File]::ReadAllText($p)
    $s = [regex]::Replace($s, "\`$WidgetVersion = '[^']*'", "`$WidgetVersion = '$ver'")
    [System.IO.File]::WriteAllText($p, $s, (New-Object System.Text.UTF8Encoding $true))
}

# The sandbox's TEMP with the junk that once hung the widget.
function New-SandboxTemp([string]$dir) {
    [void][System.IO.Directory]::CreateDirectory((Join-Path $dir 'cuw-update-1'))
    'junk' | Out-File (Join-Path $dir 'cuw-update-1\file.txt')
    'junk' | Out-File (Join-Path $dir 'cuw-usage-1.txt')
}

# Everything the sandbox started: widgets, their claude probes, self-update.
function Stop-Sandbox([string]$root) {
    foreach ($p in @(Get-CimInstance Win32_Process -ErrorAction SilentlyContinue |
                     Where-Object { $_.CommandLine -and $_.CommandLine -like "*$root*" -and $_.ProcessId -ne $PID })) {
        & taskkill.exe /PID $p.ProcessId /T /F 2>&1 | Out-Null
    }
}

function Wait-For([scriptblock]$cond, [int]$seconds) {
    $end = (Get-Date).AddSeconds($seconds)
    while ((Get-Date) -lt $end) { if (& $cond) { return $true }; Start-Sleep -Milliseconds 500 }
    return [bool](& $cond)
}

function Get-Log([string]$root) {
    $l = Join-Path $root 'widget-error.log'
    if (Test-Path $l) { return ([System.IO.File]::ReadAllText($l)).Trim() }
    return ''
}

function Report([string]$case, [bool]$ok, [string]$why) {
    if ($ok) { Write-Host "PASS  $case" -ForegroundColor Green }
    else     { Write-Host "FAIL  $case - $why" -ForegroundColor Red; $script:failed++ }
}

# Child processes take the sandbox's TEMP and the smoke mutex from here.
$env:CUW_SMOKE = '1'

foreach ($case in $Cases) {
    $root = Join-Path $Box $case
    $tmp  = Join-Path $Box "$case-temp"
    $env:TEMP = $tmp; $env:TMP = $tmp
    New-SandboxTemp $tmp
    try {
        switch ($case) {
            'start' {
                Copy-Tree $root
                Set-SmokeConfig $root
                $ready = Join-Path $Box 'start-ready.txt'
                $env:CUW_READY_FILE = $ready
                $p = Start-Process $Shell -PassThru -WindowStyle Hidden -ArgumentList '-NoProfile', '-NonInteractive',
                         '-ExecutionPolicy', 'Bypass', '-File', "`"$(Join-Path $root 'widget.ps1')`""
                $env:CUW_READY_FILE = $null
                if (-not (Wait-For { Test-Path $ready } 60)) {
                    Report $case $false "no window in 60 s$(if ($p.HasExited) { ", exited with $($p.ExitCode)" }). Log: $(Get-Log $root)"
                    break
                }
                # A few ticks of running, then: still alive, nothing in the log.
                Start-Sleep -Seconds 25
                $log = Get-Log $root
                if ($p.HasExited) { Report $case $false "exited after start with $($p.ExitCode). Log: $log" }
                elseif ($log)     { Report $case $false "errors in widget-error.log: $log" }
                else              { Report $case $true '' }
            }
            { $_ -in @('update', 'rollback') } {
                # The old copy: the working tree with a lower version.
                Copy-Tree $root
                Set-SmokeConfig $root
                Set-Version $root '0.0.1'
                # The new release: the working tree, or one that hangs at start.
                $src = Join-Path $Box "$case-release"
                Copy-Tree $src
                if ($case -eq 'rollback') {
                    $w = Join-Path $src 'widget.ps1'
                    $s = [System.IO.File]::ReadAllText($w) -replace '(?m)^\$script:Root\s*=', "Start-Sleep -Seconds 3600`r`n`$script:Root ="
                    [System.IO.File]::WriteAllText($w, $s, (New-Object System.Text.UTF8Encoding $true))
                }
                $ver = $(if ($case -eq 'rollback') { '9.9.9' } else { 'new' })
                $p = Start-Process $Shell -PassThru -WindowStyle Hidden -ArgumentList '-NoProfile', '-NonInteractive',
                         '-ExecutionPolicy', 'Bypass', '-File', "`"$(Join-Path $root 'self-update.ps1')`"",
                         '-WaitPid', '0', '-Source', "`"$src`"", '-Root', "`"$root`"", '-Version', $ver,
                         '-Zip', "`"$(Join-Path $tmp 'none.zip')`"", '-Dir', "`"$(Join-Path $tmp 'none')`"",
                         '-WaitMinutes', $(if ($case -eq 'rollback') { '1' } else { '2' })
                $p.WaitForExit()
                $current = [regex]::Match([System.IO.File]::ReadAllText((Join-Path $root 'widget.ps1')), "\`$WidgetVersion = '([^']*)'").Groups[1].Value
                $up = Wait-For { Get-ChildItem $tmp -Filter 'cuw-usage-*.txt' | Where-Object { $_.Name -ne 'cuw-usage-1.txt' } } 60
                if ($case -eq 'update') {
                    $expect = [regex]::Match([System.IO.File]::ReadAllText((Join-Path $Repo 'widget.ps1')), "\`$WidgetVersion = '([^']*)'").Groups[1].Value
                    if ($p.ExitCode -ne 0)       { Report $case $false "self-update exited with $($p.ExitCode). Log: $(Get-Log $root)" }
                    elseif ($current -ne $expect) { Report $case $false "version after update is $current, expected $expect" }
                    elseif (-not $up)             { Report $case $false 'the updated widget did not come up' }
                    else                          { Report $case $true '' }
                } else {
                    $st = $null
                    try { $st = [System.IO.File]::ReadAllText((Join-Path $root 'update-state.json')) | ConvertFrom-Json } catch {}
                    if ($current -ne '0.0.1')          { Report $case $false "version after rollback is $current, expected 0.0.1" }
                    elseif (-not $st -or $st.failed -ne '9.9.9') { Report $case $false 'update-state.json does not name the failed version' }
                    elseif (-not $up)                  { Report $case $false 'the old widget did not come back' }
                    else                               { Report $case $true '' }
                }
            }
            default { Report $case $false 'unknown case' }
        }
    } catch {
        Report $case $false $_.Exception.Message
    } finally {
        Stop-Sandbox $Box
    }
}

Stop-Sandbox $Box
Start-Sleep -Seconds 1
Remove-Item $Box -Recurse -Force -ErrorAction SilentlyContinue
if ($failed) { Write-Host "$failed failed" -ForegroundColor Red; exit 1 }
Write-Host 'all passed' -ForegroundColor Green
