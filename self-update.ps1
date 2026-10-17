<#
  Self-update of clawd-usage-winwidget, started by the widget (lib/version.ps1)
  right before it closes. Waits for the widget to exit, keeps a copy of the files
  it is about to replace, puts the new release in place and starts the widget.
  If the new version has not got as far as its first /usage request in five
  minutes, it is stopped, the old files come back and the old version starts
  again; update-state.json remembers the failed version so the widget does not
  offer it again and says what happened.
  Local files (config.json, *-state.json...) are not in the release and stay.
#>
param(
    [int]$WaitPid,
    [string]$Source,      # the unpacked release
    [string]$Root,        # the widget's folder
    [string]$Version,     # the version being installed
    [string]$Zip,         # the downloaded archive - removed at the end
    [string]$Dir,         # the folder it was unpacked to - removed at the end
    [int]$WaitMinutes = 5 # how long the new version has to come up (tools/smoke.ps1 waits less)
)

$ErrorActionPreference = 'Stop'
$ConfirmPreference     = 'None'
$Log       = Join-Path $Root 'widget-error.log'
$StatePath = Join-Path $Root 'update-state.json'

function Write-Log([string]$m) {
    try { "$(Get-Date -Format s)`tupdate: $m" | Out-File $Log -Append -Encoding utf8 } catch {}
}

function Start-Widget {
    Start-Process wscript.exe -ArgumentList "`"$(Join-Path $Root 'start-widget.vbs')`""
}

# The widget is up once it has asked /usage: it writes cuw-usage-<pid>.txt in TEMP.
function Test-WidgetUp([datetime]$since) {
    return [bool](Get-ChildItem $env:TEMP -Filter 'cuw-usage-*.txt' -ErrorAction SilentlyContinue |
                  Where-Object { $_.CreationTime -gt $since } | Select-Object -First 1)
}

# The widget then neither offers this version again nor says it is out on every start.
function Set-Failed {
    try {
        $st = @{}
        try { $j = [System.IO.File]::ReadAllText($StatePath) | ConvertFrom-Json; foreach ($p in $j.PSObject.Properties) { $st[$p.Name] = $p.Value } } catch {}
        $st.failed = $Version
        $st.failedTold = $false
        ConvertTo-Json $st | Out-File $StatePath -Encoding utf8
    } catch {}
}

function Stop-NewWidget {
    $me = Join-Path $Root 'widget.ps1'
    foreach ($p in @(Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" -ErrorAction SilentlyContinue |
                     Where-Object { $_.CommandLine -and $_.CommandLine -like "*$me*" })) {
        & taskkill.exe /PID $p.ProcessId /T /F 2>&1 | Out-Null
    }
}

try { Wait-Process -Id $WaitPid -Timeout 60 -ErrorAction SilentlyContinue } catch {}

# What the release brings, relative to its folder.
$files = @(Get-ChildItem -LiteralPath $Source -Recurse -File | ForEach-Object { $_.FullName.Substring($Source.Length).TrimStart('\') })
$bak   = Join-Path ([System.IO.Path]::GetTempPath()) "clawd-backup-$WaitPid"
$added = @()

function Restore-Old {
    foreach ($rel in $files) {
        $old = Join-Path $bak $rel
        $dst = Join-Path $Root $rel
        try {
            if (Test-Path -LiteralPath $old) { Copy-Item -LiteralPath $old -Destination $dst -Force }
            elseif ($added -contains $rel)   { Remove-Item -LiteralPath $dst -Force }
        } catch { Write-Log "restore $rel`: $($_.Exception.Message)" }
    }
}

try {
    if (Test-Path $bak) { Remove-Item $bak -Recurse -Force }
    foreach ($rel in $files) {
        $dst = Join-Path $Root $rel
        if (Test-Path -LiteralPath $dst) {
            $to = Join-Path $bak $rel
            [void][System.IO.Directory]::CreateDirectory((Split-Path -Parent $to))
            Copy-Item -LiteralPath $dst -Destination $to -Force
        } else {
            $added += $rel
        }
    }
    foreach ($rel in $files) {
        $dst = Join-Path $Root $rel
        [void][System.IO.Directory]::CreateDirectory((Split-Path -Parent $dst))
        Copy-Item -LiteralPath (Join-Path $Source $rel) -Destination $dst -Force
    }
} catch {
    Write-Log "could not put $Version in place, keeping the old version: $($_.Exception.Message)"
    Restore-Old
    Set-Failed
    Start-Widget
    exit 1
}

$since = Get-Date
Start-Widget
# Five minutes by default: with runAsAdmin the new copy first waits for the UAC answer.
$deadline = $since.AddMinutes($WaitMinutes)
while ((Get-Date) -lt $deadline -and -not (Test-WidgetUp $since)) { Start-Sleep -Seconds 2 }

if (Test-WidgetUp $since) {
    foreach ($p in @($Zip, $Dir, $bak)) {
        if ($p) { Remove-Item -LiteralPath $p -Recurse -Force -ErrorAction SilentlyContinue }
    }
    exit 0
}

Write-Log "$Version did not start in $WaitMinutes min - rolled back to the old version"
Stop-NewWidget
Restore-Old
Set-Failed
Start-Widget
