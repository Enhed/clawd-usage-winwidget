# -------------------------------------------------------------- advisor ----
# Clawd as a small housekeeper: every advisorIntervalMinutes a background scan looks
# at the computer - disk space and what takes it, new autostart entries, apps not
# started for a long time, a pending restart, processes hogging memory or CPU - and
# a lamp with the number of tips lights up in the header; it opens a panel with
# them. Read-only and local: nothing is deleted or changed, a link only opens the
# right place. No network, no tokens.

$script:AdvStatePath = Join-Path $script:Root 'advisor-state.json'
$script:AdvJob    = $null   # @{ ps; handle } of the running scan
$script:AdvTry    = (Get-Date).AddMinutes(-([double]$script:Cfg.advisorIntervalMinutes)).AddSeconds(60)
$script:AdvScan   = $null   # result of the last scan
$script:AdvAt     = $null   # when the last scan finished
$script:AdvSeen   = @{}     # sigs already shown in this run - Clawd waves only at new ones
$script:AdvCpu    = @()     # CPU hogs from the previous scan: one busy sample is not a hog yet

function Load-AdvisorState {
    $st = @{ snooze = @{}; startupKnown = $null }
    try {
        $raw = [System.IO.File]::ReadAllText($script:AdvStatePath, [System.Text.Encoding]::UTF8) | ConvertFrom-Json
        foreach ($p in $raw.snooze.PSObject.Properties) { $st.snooze[$p.Name] = [datetime]$p.Value }
        if ($null -ne $raw.startupKnown) { $st.startupKnown = @($raw.startupKnown) }
    } catch {}
    return $st
}

function Save-AdvisorState {
    try {
        $snooze = [ordered]@{}
        foreach ($k in $script:AdvState.snooze.Keys) { $snooze[$k] = $script:AdvState.snooze[$k].ToString('s') }
        [PSCustomObject]@{ snooze = [PSCustomObject]$snooze; startupKnown = $script:AdvState.startupKnown } |
            ConvertTo-Json -Depth 3 | Out-File $script:AdvStatePath -Encoding utf8
    } catch {}
}

$script:AdvState = Load-AdvisorState

# The scan runs in a separate runspace: folder sizes and a CPU sample take seconds,
# the window must not freeze meanwhile. Returns plain data, texts are made on display.
$AdvisorScan = {
    param($opt)
    $GB = 1GB

    function Get-DirSize([string]$path) {
        $total = [int64]0
        if (-not $path -or -not [System.IO.Directory]::Exists($path)) { return $total }
        $stack = New-Object System.Collections.Stack
        $stack.Push((New-Object System.IO.DirectoryInfo $path))
        while ($stack.Count) {
            $d = $stack.Pop()
            try {
                foreach ($i in $d.EnumerateFileSystemInfos()) {
                    # Junctions and symlinks lead to places counted elsewhere (or loops).
                    if ($i.Attributes -band [System.IO.FileAttributes]::ReparsePoint) { continue }
                    if ($i -is [System.IO.DirectoryInfo]) { $stack.Push($i) } else { $total += $i.Length }
                }
            } catch {}
        }
        return $total
    }

    $r = @{ disks = @(); junk = @(); startup = @(); apps = @(); reboot = $false
            uptimeDays = 0; mem = @(); cpu = @() }

    # --- disks ---------------------------------------------------------------
    $fixed = @([System.IO.DriveInfo]::GetDrives() | Where-Object { $_.DriveType -eq 'Fixed' -and $_.IsReady })
    foreach ($d in $fixed) {
        $pct = [math]::Round(100.0 * $d.AvailableFreeSpace / $d.TotalSize)
        if ($d.AvailableFreeSpace -lt $opt.diskGB * $GB -or $pct -lt 5) {
            $r.disks += @{ drive = $d.Name.TrimEnd('\'); free = $d.AvailableFreeSpace / $GB; pct = $pct }
        }
    }

    # --- what takes space: only places that are safe to look through --------
    $sid  = [System.Security.Principal.WindowsIdentity]::GetCurrent().User.Value
    $dl   = $null
    try {
        $dl = (Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\User Shell Folders' -ErrorAction Stop).'{374DE290-123F-4565-9164-39C4925E467B}'
        $dl = [Environment]::ExpandEnvironmentVariables($dl)
    } catch {}
    if (-not $dl) { $dl = Join-Path $env:USERPROFILE 'Downloads' }
    $places = @(
        @{ id = 'temp';      path = $env:TEMP }
        @{ id = 'downloads'; path = $dl }
        @{ id = 'dumps';     path = Join-Path $env:LOCALAPPDATA 'CrashDumps' }
        @{ id = 'npm';       path = Join-Path $env:LOCALAPPDATA 'npm-cache' }
        @{ id = 'pip';       path = Join-Path $env:LOCALAPPDATA 'pip\Cache' }
        @{ id = 'yarn';      path = Join-Path $env:LOCALAPPDATA 'Yarn\Cache' }
        @{ id = 'scoop';     path = Join-Path $env:USERPROFILE 'scoop\cache' }
    )
    if ($opt.admin) {
        $places += @{ id = 'wintemp'; path = Join-Path $env:windir 'Temp' }
        $places += @{ id = 'wudl';    path = Join-Path $env:windir 'SoftwareDistribution\Download' }
    }
    foreach ($p in $places) {
        $size = Get-DirSize $p.path
        if ($size -gt 0) { $r.junk += @{ id = $p.id; path = $p.path; size = $size / $GB } }
    }
    $bin = [int64]0
    foreach ($d in $fixed) { $bin += Get-DirSize (Join-Path $d.RootDirectory.FullName "`$Recycle.Bin\$sid") }
    if ($bin -gt 0) { $r.junk += @{ id = 'recycle'; path = 'shell:RecycleBinFolder'; size = $bin / $GB } }

    # --- autostart: Run keys and Startup folders, minus what is switched off --
    $approvedOff = @{}
    foreach ($hive in 'HKCU:', 'HKLM:') {
        foreach ($sub in 'Run', 'Run32', 'StartupFolder') {
            $k = "$hive\Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\$sub"
            try {
                $item = Get-Item $k -ErrorAction Stop
                foreach ($n in $item.GetValueNames()) {
                    $b = $item.GetValue($n)
                    # Odd first byte - disabled in Task Manager / Settings.
                    if ($b -is [byte[]] -and $b.Length -and ($b[0] -band 1)) { $approvedOff[$n] = $true }
                }
            } catch {}
        }
    }
    foreach ($k in 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run',
                   'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run',
                   'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Run') {
        try {
            $item = Get-Item $k -ErrorAction Stop
            foreach ($n in $item.GetValueNames()) { if ($n -and -not $approvedOff[$n]) { $r.startup += $n } }
        } catch {}
    }
    foreach ($f in @([Environment]::GetFolderPath('Startup'), [Environment]::GetFolderPath('CommonStartup'))) {
        foreach ($i in @(Get-ChildItem $f -File -ErrorAction SilentlyContinue)) {
            if ($i.Name -eq 'desktop.ini' -or $approvedOff[$i.Name]) { continue }
            $r.startup += [System.IO.Path]::GetFileNameWithoutExtension($i.Name)
        }
    }
    $r.startup = @($r.startup | Sort-Object -Unique)

    # --- apps not started for a long time ------------------------------------
    # When a program was last started, Windows keeps in UserAssist (launches from
    # Explorer, Start and the taskbar). Paths there start with known folder GUIDs;
    # taskbar and Start entries are shortcuts - resolved to their targets.
    $kf = @{
        '{6D809377-6AF0-444B-8957-A3773F02200E}' = $env:ProgramW6432
        '{7C5A40EF-A0FB-4BFC-874A-C0F2E0B9FA8E}' = ${env:ProgramFiles(x86)}
        '{F38BF404-1D43-42F2-9305-67DE0B28FC23}' = $env:windir
        '{1AC14E77-02E7-4E5D-B744-2EB1AE5198B7}' = Join-Path $env:windir 'System32'
        '{D65231B0-B2F1-4857-A4CE-A8E7C6EA7D27}' = Join-Path $env:windir 'SysWOW64'
        '{0139D44E-6AFE-49F2-8690-3DAFCAE6FFB8}' = [Environment]::GetFolderPath('CommonPrograms')
        '{A77F5D77-2E2B-44C3-A6A2-ABA601054A51}' = [Environment]::GetFolderPath('Programs')
        '{9E3995AB-1F9C-4F13-B827-48B24B6C7174}' = Join-Path $env:APPDATA 'Microsoft\Internet Explorer\Quick Launch\User Pinned'
        '{B4BFCC3A-DB2C-424C-B029-7FE99A87C641}' = [Environment]::GetFolderPath('Desktop')
    }
    $rot13 = {
        param($s)
        $a = $s.ToCharArray()
        for ($i = 0; $i -lt $a.Length; $i++) {
            $c = [int]$a[$i]
            if ($c -ge 65 -and $c -le 90)      { $a[$i] = [char]((($c - 65 + 13) % 26) + 65) }
            elseif ($c -ge 97 -and $c -le 122) { $a[$i] = [char]((($c - 97 + 13) % 26) + 97) }
        }
        -join $a
    }
    $shell = $null
    try { $shell = New-Object -ComObject WScript.Shell } catch {}
    $used = @{}   # lower-case exe path -> last start
    $ua = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\UserAssist'
    foreach ($g in @(Get-ChildItem $ua -ErrorAction SilentlyContinue)) {
        try { $k = Get-Item (Join-Path $g.PSPath 'Count') -ErrorAction Stop } catch { continue }
        foreach ($n in $k.GetValueNames()) {
            $d = $k.GetValue($n)
            if (-not ($d -is [byte[]]) -or $d.Length -lt 68) { continue }
            $ft = [BitConverter]::ToInt64($d, 60)
            if ($ft -le 0) { continue }
            $path = & $rot13 $n
            $m = [regex]::Match($path, '^(\{[0-9A-Fa-f-]{36}\})(.*)$')
            if ($m.Success -and $kf[$m.Groups[1].Value.ToUpper()]) { $path = $kf[$m.Groups[1].Value.ToUpper()] + $m.Groups[2].Value }
            if ($path -like '*.lnk' -and $shell) {
                try { $t = $shell.CreateShortcut($path).TargetPath; if ($t) { $path = $t } } catch {}
            }
            $when = [datetime]::FromFileTime($ft)
            $key = $path.ToLower()
            if (-not $used[$key] -or $used[$key] -lt $when) { $used[$key] = $when }
        }
    }
    foreach ($p in @(Get-Process -ErrorAction SilentlyContinue)) {
        try { if ($p.Path) { $used[$p.Path.ToLower()] = Get-Date } } catch {}
    }
    # Elevated: Prefetch knows every start of every program, terminal ones too -
    # "NAME.EXE-HASH.pf", written at each start. Only the file name is known, so
    # generic names (installers, updaters) say nothing about a particular app.
    $pf = @{}
    if ($opt.admin) {
        foreach ($f in @(Get-ChildItem (Join-Path $env:windir 'Prefetch') -Filter *.pf -ErrorAction SilentlyContinue)) {
            $m = [regex]::Match($f.Name, '^(.+\.EXE)-[0-9A-F]{8}\.pf$')
            if (-not $m.Success) { continue }
            $exe = $m.Groups[1].Value.ToLower()
            if ($exe -match '^(unins|uninstall|setup|install|update|updater|helper|crashpad|elevation_service|notification_helper)') { continue }
            if (-not $pf[$exe] -or $pf[$exe] -lt $f.LastWriteTime) { $pf[$exe] = $f.LastWriteTime }
        }
    }
    # Command-line tools and services are used without Explorer seeing it: an app
    # with a folder in PATH or a service running from it counts as in use.
    $inUse = @()
    foreach ($p in ([Environment]::GetEnvironmentVariable('Path', 'Machine') + ';' +
                    [Environment]::GetEnvironmentVariable('Path', 'User')) -split ';') {
        if ($p) { $inUse += [Environment]::ExpandEnvironmentVariables($p).Trim('"').TrimEnd('\').ToLower() }
    }
    try {
        foreach ($s in @(Get-CimInstance Win32_Service -ErrorAction Stop)) {
            $m = [regex]::Match([string]$s.PathName, '^"?([^"]+?\.exe)')
            if ($m.Success) { $inUse += (Split-Path -Parent $m.Groups[1].Value).ToLower() }
        }
    } catch {}
    $cut = (Get-Date).AddDays(-[double]$opt.unusedDays)
    $seenApps = @{}
    foreach ($root in 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
                      'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*',
                      'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*') {
        foreach ($a in @(Get-ItemProperty $root -ErrorAction SilentlyContinue)) {
            $name = [string]$a.DisplayName
            if (-not $name -or $a.SystemComponent -eq 1 -or $a.ParentKeyName -or $a.ReleaseType) { continue }
            if ($seenApps[$name]) { continue }
            # Drivers, runtimes and the like are not "apps you forgot about".
            if ($name -match 'Redistributable|Runtime|Driver|SDK|Update|Helper|Service') { continue }
            if ([string]$a.Publisher -match 'Microsoft|NVIDIA|Intel|Advanced Micro|AMD|Realtek') { continue }
            $sizeKB = [double]$a.EstimatedSize
            if ($sizeKB -lt $opt.appMinMB * 1024) { continue }
            $dir = [string]$a.InstallLocation
            if (-not $dir -and $a.DisplayIcon) {
                $icon = ([string]$a.DisplayIcon -replace ',\s*-?\d+$', '').Trim('"')
                if ($icon -like '*.exe') { $dir = Split-Path -Parent $icon }
            }
            if (-not $dir) { continue }
            $dir = $dir.Trim('"').TrimEnd('\').ToLower()
            if (-not $dir -or $dir -like '*\package cache*' -or -not [System.IO.Directory]::Exists($dir)) { continue }
            # Installed recently - too early to call it unused.
            $installed = $null
            try { $installed = [datetime]::ParseExact([string]$a.InstallDate, 'yyyyMMdd', $null) } catch {}
            if (-not $installed) { try { $installed = [System.IO.Directory]::GetCreationTime($dir) } catch {} }
            if ($installed -and $installed -gt $cut) { continue }
            $last = $null
            foreach ($u in $used.Keys) {
                if ($u.StartsWith($dir + '\') -and (-not $last -or $used[$u] -gt $last)) { $last = $used[$u] }
            }
            if ($pf.Count) {
                foreach ($exe in @(Get-ChildItem $dir -Filter *.exe -Recurse -Depth 2 -ErrorAction SilentlyContinue | Select-Object -First 200)) {
                    $t = $pf[$exe.Name.ToLower()]
                    if ($t -and (-not $last -or $t -gt $last)) { $last = $t }
                }
            }
            if ($last -and $last -gt $cut) { continue }
            $busy = $false
            foreach ($u in $inUse) { if ($u -eq $dir -or $u.StartsWith($dir + '\')) { $busy = $true; break } }
            if ($busy) { continue }
            $seenApps[$name] = $true
            $r.apps += @{ name = $name; size = $sizeKB / 1MB; last = $last }
        }
    }
    $r.apps = @($r.apps | Sort-Object { $_.size } -Descending)

    # --- system: pending restart, uptime, memory and CPU hogs ----------------
    foreach ($k in 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired',
                   'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending') {
        if (Test-Path $k) { $r.reboot = $true }
    }
    $os = $null
    try { $os = Get-CimInstance Win32_OperatingSystem -ErrorAction Stop } catch {}
    if ($os) {
        # Fast Startup keeps the kernel across "shut down" - this counts from a real restart.
        $r.uptimeDays = [math]::Floor(((Get-Date) - $os.LastBootUpTime).TotalDays)
        $ram = [double]$os.TotalVisibleMemorySize * 1KB
        # Private working set, as Task Manager shows it. WorkingSet64 also counts pages
        # shared with other processes (DLLs, shared memory), so summed over a browser's
        # dozens of processes the same pages count many times over.
        $private = @{}
        try {
            foreach ($c in Get-CimInstance Win32_PerfRawData_PerfProc_Process -ErrorAction Stop) {
                # Idle and _Total both come as process 0.
                if ($c.IDProcess) { $private[[int]$c.IDProcess] = [double]$c.WorkingSetPrivate }
            }
        } catch {}
        $groups = Get-Process -ErrorAction SilentlyContinue | Group-Object Name
        foreach ($g in $groups) {
            $ws = 0.0
            foreach ($p in $g.Group) {
                if ($private.ContainsKey($p.Id)) { $ws += $private[$p.Id] } else { $ws += [double]$p.PrivateMemorySize64 }
            }
            if ($ws -ge $ram * $opt.memPercent / 100) {
                $desc = $g.Name
                try { $x = @($g.Group | Where-Object { $_.Description } | Select-Object -First 1); if ($x) { $desc = $x[0].Description } } catch {}
                $r.mem += @{ name = $desc; size = $ws / $GB; pct = [math]::Round(100 * $ws / $ram) }
            }
        }
    }
    $t0 = @{}
    foreach ($p in @(Get-Process -ErrorAction SilentlyContinue)) {
        try { if ($p.TotalProcessorTime) { $t0["$($p.Id)"] = $p.TotalProcessorTime.TotalSeconds } } catch {}
    }
    $sample = 10
    Start-Sleep -Seconds $sample
    $byName = @{}
    $descs  = @{}
    foreach ($p in @(Get-Process -ErrorAction SilentlyContinue)) {
        if ($p.Id -eq 0 -or $null -eq $t0["$($p.Id)"]) { continue }
        try {
            $d = $p.TotalProcessorTime.TotalSeconds - $t0["$($p.Id)"]
            $byName[$p.Name] += $d
            if (-not $descs[$p.Name] -and $p.Description) { $descs[$p.Name] = $p.Description }
        } catch {}
    }
    foreach ($n in $byName.Keys) {
        $core = [math]::Round(100 * $byName[$n] / $sample)
        if ($core -ge $opt.cpuPercent) {
            $desc = $descs[$n]; if (-not $desc) { $desc = $n }
            $r.cpu += @{ id = $n; name = $desc; core = $core }
        }
    }
    return $r
}

function Start-AdvisorScan {
    if ($script:AdvJob) { return }
    $script:AdvTry = Get-Date
    $opt = @{
        diskGB     = [double]$script:Cfg.advisorDiskGB
        unusedDays = [double]$script:Cfg.advisorUnusedDays
        appMinMB   = 100
        admin      = [bool]$script:IsAdmin   # elevated: Prefetch and system folders too
        memPercent = [double]$script:Cfg.advisorMemPercent
        cpuPercent = 80
    }
    $ps = [powershell]::Create()
    [void]$ps.AddScript($AdvisorScan.ToString()).AddArgument($opt)
    $script:AdvJob = @{ ps = $ps; handle = $ps.BeginInvoke() }
}

function Collect-AdvisorScan {
    $job = $script:AdvJob
    if (-not $job -or -not $job.handle.IsCompleted) { return }
    $script:AdvJob = $null
    try {
        $out = $job.ps.EndInvoke($job.handle)
        if ($out.Count) {
            $prevCpu = $script:AdvCpu
            $script:AdvScan = $out[0]
            $script:AdvAt   = Get-Date
            $script:AdvCpu  = @($out[0].cpu | ForEach-Object { $_.id })
            # A hog is one seen busy in two scans in a row.
            $script:AdvScan.cpu = @($out[0].cpu | Where-Object { $prevCpu -contains $_.id })
            if ($null -eq $script:AdvState.startupKnown) {
                # First run: what is in autostart now is the baseline, only new entries are news.
                $script:AdvState.startupKnown = @($out[0].startup)
                Save-AdvisorState
            }
        }
        Write-TipsFile
        if ($job.ps.Streams.Error.Count) { throw $job.ps.Streams.Error[0].Exception }
    } catch {
        try {
            "$(Get-Date -Format s)`tadvisor: $($_.Exception.Message)" |
                Out-File (Join-Path $script:Root 'widget-error.log') -Append -Encoding utf8
        } catch {}
    } finally {
        $job.ps.Dispose()
    }
}

function Format-GB([double]$gb) {
    if ($gb -ge 10) { return ('{0:0}' -f $gb) }
    return ('{0:0.#}' -f $gb)
}

# Tips from the last scan, most important first. Each: sig (what a dismissal
# remembers), text, action (what a click opens) and how long a dismissal lasts.
function Get-AdvisorTips {
    $s = $script:AdvScan
    if (-not $s -or -not $script:Cfg.showAdvisor) { return @() }
    $tips = @()
    foreach ($d in $s.disks) {
        $tips += @{ sig = "disk|$($d.drive)"; text = (T 'adv.disk') -f $d.drive, (Format-GB $d.free), $d.pct
                    act = 'ms-settings:storagesense'; actKey = 'adv.act.storage'; warn = $true; hours = 24 }
    }
    if ($s.reboot) {
        $tips += @{ sig = 'reboot'; text = T 'adv.reboot'; act = 'ms-settings:windowsupdate'; actKey = 'adv.act.update'; hours = 24 }
    }
    foreach ($c in $s.cpu) {
        $tips += @{ sig = "cpu|$($c.id)"; text = (T 'adv.cpu') -f $c.name, $c.core
                    act = 'taskmgr.exe'; actKey = 'adv.act.taskmgr'; hours = 24 }
    }
    foreach ($m in $s.mem) {
        $tips += @{ sig = "mem|$($m.name)"; text = (T 'adv.mem') -f $m.name, (Format-GB $m.size), $m.pct
                    act = 'taskmgr.exe'; actKey = 'adv.act.taskmgr'; hours = 24 }
    }
    $known = @($script:AdvState.startupKnown)
    $new = @($s.startup | Where-Object { $known -notcontains $_ })
    if ($new.Count) {
        $tips += @{ sig = 'startup|' + ($new -join '|'); text = (T 'adv.startup') -f (($new | Select-Object -First 3) -join ', ')
                    act = 'ms-settings:startupapps'; actKey = 'adv.act.startup'; startup = $true
                    ctx = 'new autostart entries: ' + ($new -join '; ') }
    }
    $junk = @($s.junk | Sort-Object { $_.size } -Descending)
    $total = 0.0; foreach ($j in $junk) { $total += $j.size }
    if ($junk.Count -and $total -ge [double]$script:Cfg.advisorJunkGB) {
        $list = ($junk | Select-Object -First 3 | ForEach-Object { "$(T "adv.place.$($_.id)") $(Format-GB $_.size) $(T 'adv.gb')" }) -join ', '
        $tips += @{ sig = 'junk'; text = (T 'adv.junk') -f (Format-GB $total), $list
                    act = $junk[0].path; actKey = "adv.act.open"; actArg = (T "adv.place.$($junk[0].id)"); hours = 72
                    ctx = ($junk | ForEach-Object { "$($_.id) $($_.path) $('{0:0.00}' -f $_.size) GB" }) -join '; ' }
    }
    if ($s.apps.Count) {
        $list = ($s.apps | Select-Object -First 3 | ForEach-Object { "$($_.name) ($(Format-GB $_.size) $(T 'adv.gb'))" }) -join ', '
        $tips += @{ sig = 'apps|' + (($s.apps | ForEach-Object { $_.name }) -join '|')
                    text = (T 'adv.apps') -f [int]$script:Cfg.advisorUnusedDays, $list
                    act = 'ms-settings:appsfeatures'; actKey = 'adv.act.apps'; hours = 24 * 30
                    ctx = 'all unused: ' + (($s.apps | ForEach-Object {
                        "$($_.name) $('{0:0.00}' -f $_.size) GB, last start $(if ($_.last) { $_.last.ToString('yyyy-MM-dd') } else { 'unknown' })" }) -join '; ') }
    }
    if (-not $s.reboot -and $s.uptimeDays -ge [double]$script:Cfg.advisorUptimeDays) {
        $tips += @{ sig = 'uptime'; text = (T 'adv.uptime') -f $s.uptimeDays; hours = 24 * 3 }
    }
    $now = Get-Date
    return @($tips | Where-Object {
        $until = $script:AdvState.snooze[$_.sig]
        -not $until -or $until -lt $now
    })
}

# The tips as a file in Clawd's home - for his own session (the phone does not
# see the widget). Rewritten after each check and dismissal.
function Write-TipsFile {
    $lines = @("# Clawd's tips", '',
               "Written by the clawd-usage-winwidget widget after each look over the computer (every $($script:Cfg.advisorIntervalMinutes) min); do not edit.",
               "Last check: $(if ($script:AdvAt) { $script:AdvAt.ToString('yyyy-MM-dd HH:mm') } else { 'none yet' }). Widget elevated: $(if ($script:IsAdmin) { 'yes' } else { 'no' }).", '')
    $tips = @(Get-AdvisorTips)
    if (-not $tips.Count) { $lines += 'Nothing to suggest right now.' }
    foreach ($t in $tips) {
        $lines += "- $($t.text)"
        if ($t.ctx) { $lines += "  Details: $($t.ctx)" }
    }
    try {
        [System.IO.File]::WriteAllText((Join-Path (Get-ClawdHome) 'tips.md'), ($lines -join "`r`n") + "`r`n",
                                       (New-Object System.Text.UTF8Encoding $false))
    } catch {}
}

# Dismissed - not shown again for a while; new autostart entries become known instead.
function Close-AdvisorTip($tip) {
    if (-not $tip) { return }
    if ($tip.startup) {
        $script:AdvState.startupKnown = @($script:AdvScan.startup)
    } else {
        $script:AdvState.snooze[$tip.sig] = (Get-Date).AddHours($tip.hours)
    }
    # Forget expired dismissals so the file does not grow forever.
    $now = Get-Date
    foreach ($k in @($script:AdvState.snooze.Keys)) {
        if ($script:AdvState.snooze[$k] -lt $now) { $script:AdvState.snooze.Remove($k) }
    }
    Save-AdvisorState
    Write-TipsFile
    Update-Panel
    Update-Badge
}

function Update-Advisor {
    Collect-AdvisorScan
    if (-not $script:Cfg.showAdvisor) { return }
    if (([datetime]::Now - $script:AdvTry).TotalMinutes -ge [double]$script:Cfg.advisorIntervalMinutes) {
        Start-AdvisorScan
    }
    # Something new to say - Clawd waves to draw attention, if he is free and awake.
    $fresh = @(Get-AdvisorTips | Where-Object { -not $script:AdvSeen[$_.sig] })
    foreach ($t in $fresh) { $script:AdvSeen[$t.sig] = $true }
    if ($fresh.Count) {
        $m = $script:Mz
        if ($script:Cfg.showMascot -and -not $m.act -and -not $m.buried -and $m.mood -ne 'dead') {
            Start-MascotAct 'wave'
        }
    }
}
