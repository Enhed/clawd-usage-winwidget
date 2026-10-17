# --------------------------------------------------------------- history ----
# The details show how the 5-hour and weekly percentages went over the last 7
# days, and which projects spent the most. Each /usage reply is a sample in
# usage-history.json; on the first run the history is filled from the
# transcripts that /usage probes of earlier versions left in ~/.claude/projects
# (one per probe, before --no-session-persistence). Projects come from the Claude
# Code transcripts: tokens weighted by the model's price, so the shares roughly
# follow what eats the limits. Hovering the chart tells which project was busiest
# in that hour. Both scans run in a background runspace.

$script:HistPath = Join-Path $script:Root 'usage-history.json'
$HistKeepDays    = 8
$HistStepMinutes = 5      # an unchanged value is sampled this often
$HistGapMinutes  = 20     # a longer pause between samples - the widget was off: the line breaks
$HistChartHeight = 44.0
$ProjScanMinutes = 15
$script:Hist     = @{ samples = New-Object System.Collections.ArrayList; backfilled = $false }
$script:HistJob  = $null  # @{ ps; handle; kind } of the running scan
$script:HistKey  = $null  # what the chart was last drawn from
$script:ProjTry  = [datetime]::MinValue
$script:ProjAt   = $null
$script:ProjCache = @{}   # per transcript: bytes read, message ids, weights by hour - kept between scans
$script:Proj     = $null  # @{ total = @{ name = weight }; hours = @{ hour = @{ name = weight } }; paths = @{ name = cwd } }

function Get-UnixMinute([datetime]$t) { return [int][math]::Floor(([DateTimeOffset]$t).ToUnixTimeSeconds() / 60) }
function ConvertFrom-UnixMinute([int]$m) { return [DateTimeOffset]::FromUnixTimeSeconds([int64]$m * 60).LocalDateTime }

# Path data must use a dot whatever the UI culture is.
function Format-Coord([double]$v) { return $v.ToString('0.##', [System.Globalization.CultureInfo]::InvariantCulture) }

# A sample is @(unix minute, session %, week %); -1 - no value.
function Load-History {
    try {
        $raw = [System.IO.File]::ReadAllText($script:HistPath, [System.Text.Encoding]::UTF8) | ConvertFrom-Json
        $script:Hist.backfilled = [bool]$raw.backfilled
        foreach ($s in @($raw.samples)) { [void]$script:Hist.samples.Add(@([int]$s[0], [int]$s[1], [int]$s[2])) }
    } catch {}
}

function Save-History {
    try {
        $cut = Get-UnixMinute ((Get-Date).AddDays(-$HistKeepDays))
        while ($script:Hist.samples.Count -and $script:Hist.samples[0][0] -lt $cut) { $script:Hist.samples.RemoveAt(0) }
        $rows = @($script:Hist.samples | ForEach-Object { '[{0},{1},{2}]' -f $_[0], $_[1], $_[2] })
        $flag = $(if ($script:Hist.backfilled) { 'true' } else { 'false' })
        [System.IO.File]::WriteAllText($script:HistPath, '{"backfilled":' + $flag + ',"samples":[' + ($rows -join ',') + ']}')
    } catch {}
}

Load-History

# Called by Collect-UsageProbe with every reply.
function Add-UsageSample($u) {
    $s = $(if ($null -ne $u.session) { [int]$u.session } else { -1 })
    $w = $(if ($null -ne $u.week) { [int]$u.week } else { -1 })
    $now = Get-UnixMinute (Get-Date)
    $n = $script:Hist.samples.Count
    if ($n) {
        $last = $script:Hist.samples[$n - 1]
        if ($last[1] -eq $s -and $last[2] -eq $w -and $now - $last[0] -lt $HistStepMinutes) { return }
    }
    [void]$script:Hist.samples.Add(@($now, $s, $w))
    Save-History
}

# The transcripts of the old /usage probes: the project folder of the widget's own
# directory, named the way Claude Code names it - every other character a dash.
$HistBackfill = {
    param($dir, $since)
    $out = New-Object System.Collections.ArrayList
    if (-not [System.IO.Directory]::Exists($dir)) { return ,$out }
    $from = [DateTimeOffset]::FromUnixTimeSeconds([int64]$since * 60).UtcDateTime
    foreach ($f in (New-Object System.IO.DirectoryInfo $dir).EnumerateFiles('*.jsonl')) {
        if ($f.LastWriteTimeUtc -lt $from -or $f.Length -gt 65536) { continue }
        try { $t = [System.IO.File]::ReadAllText($f.FullName) } catch { continue }
        if ($t.IndexOf('<command-name>/usage</command-name>') -lt 0) { continue }
        $s  = [regex]::Match($t, 'Current session:\s*(\d+)%')
        $w  = [regex]::Match($t, 'Current week \(all models\):\s*(\d+)%')
        $ts = [regex]::Match($t, '"timestamp":"([^"]+)"')
        if (-not ($s.Success -or $w.Success) -or -not $ts.Success) { continue }
        try { $at = [DateTimeOffset]::Parse($ts.Groups[1].Value, [System.Globalization.CultureInfo]::InvariantCulture) } catch { continue }
        [void]$out.Add(@([int][math]::Floor($at.ToUnixTimeSeconds() / 60),
                         $(if ($s.Success) { [int]$s.Groups[1].Value } else { -1 }),
                         $(if ($w.Success) { [int]$w.Groups[1].Value } else { -1 })))
    }
    return ,$out
}

# Tokens of every assistant reply since $since, by project folder and hour. Only
# what was appended since the last scan is read; a reply is written as several
# lines with the same message id - counted once.
$ProjScan = {
    param($root, $cache, $since)
    # Price of a million input tokens; the first match wins, so versions go first.
    $prices = @(@('fable', 10), @('mythos', 10), @('opus-5-5', 4), @('opus', 5),
                @('sonnet-5', 2), @('sonnet', 3), @('haiku-5', 0.1), @('haiku', 1))
    # Cache writes, cache reads and output relative to input.
    $kinds  = @(@('input_tokens', 1), @('cache_creation_input_tokens', 1.25),
                @('cache_read_input_tokens', 0.1), @('output_tokens', 5))
    $from  = [DateTimeOffset]::FromUnixTimeSeconds([int64]$since * 60).UtcDateTime
    $first = [int][math]::Floor($since / 60)
    $seen  = @{}
    if ([System.IO.Directory]::Exists($root)) {
        foreach ($pd in (New-Object System.IO.DirectoryInfo $root).EnumerateDirectories()) {
            foreach ($f in $pd.EnumerateFiles('*.jsonl', [System.IO.SearchOption]::AllDirectories)) {
                if ($f.LastWriteTimeUtc -lt $from) { continue }
                $seen[$f.FullName] = $true
                $c = $cache[$f.FullName]
                if (-not $c -or $f.Length -lt $c.pos) {
                    $c = @{ pos = [int64]0; ids = @{}; dir = $pd.Name; cwd = $null; w = @{} }
                    $cache[$f.FullName] = $c
                }
                if ($f.Length -eq $c.pos) { continue }
                try {
                    $fs = New-Object System.IO.FileStream($f.FullName, 'Open', 'Read', 'ReadWrite')
                    try {
                        [void]$fs.Seek($c.pos, 'Begin')
                        $text = (New-Object System.IO.StreamReader($fs, [System.Text.Encoding]::UTF8)).ReadToEnd()
                    } finally { $fs.Dispose() }
                } catch { continue }
                # A line still being written waits for the next scan.
                $end = $text.LastIndexOf("`n")
                if ($end -lt 0) { continue }
                $text = $text.Substring(0, $end + 1)
                $c.pos += [System.Text.Encoding]::UTF8.GetByteCount($text)
                foreach ($line in $text.Split("`n")) {
                    if (-not $c.cwd) {
                        $x = [regex]::Match($line, '"cwd":"((?:[^"\\]|\\.)*)"')
                        if ($x.Success) { $c.cwd = $x.Groups[1].Value.Replace('\\', '\') }
                    }
                    if ($line.IndexOf('"usage":{"input_tokens"', [StringComparison]::Ordinal) -lt 0) { continue }
                    $id = [regex]::Match($line, '"id":"(msg_[^"]+)"')
                    if ($id.Success) {
                        if ($c.ids.ContainsKey($id.Groups[1].Value)) { continue }
                        $c.ids[$id.Groups[1].Value] = 1
                    }
                    $model = [regex]::Match($line, '"model":"([^"]+)"').Groups[1].Value
                    if ($model -eq '<synthetic>') { continue }
                    $ts = [regex]::Match($line, '"timestamp":"([^"]+)"')
                    if (-not $ts.Success) { continue }
                    try { $at = [DateTimeOffset]::Parse($ts.Groups[1].Value, [System.Globalization.CultureInfo]::InvariantCulture) } catch { continue }
                    $hour = [int][math]::Floor($at.ToUnixTimeSeconds() / 3600)
                    if ($hour -lt $first) { continue }
                    $price = 3
                    foreach ($p in $prices) { if ($model.Contains($p[0])) { $price = $p[1]; break } }
                    $tok = 0.0
                    foreach ($k in $kinds) {
                        $v = [regex]::Match($line, '"' + $k[0] + '":(\d+)')
                        if ($v.Success) { $tok += $k[1] * [double]$v.Groups[1].Value }
                    }
                    $c.w[$hour] = [double]$c.w[$hour] + $price * $tok
                }
            }
        }
    }
    # Transcripts that fell out of the week are forgotten.
    foreach ($k in @($cache.Keys)) { if (-not $seen[$k]) { $cache.Remove($k) } }

    # A project is a folder in ~/.claude/projects, shown by the last part of its path.
    $cwds = @{}
    foreach ($c in $cache.Values) { if ($c.cwd -and -not $cwds[$c.dir]) { $cwds[$c.dir] = $c.cwd } }
    $userHome = $env:USERPROFILE.TrimEnd('\')
    $r = @{ total = @{}; hours = @{}; paths = @{} }
    foreach ($c in $cache.Values) {
        $cwd = $cwds[$c.dir]
        if (-not $cwd) { $cwd = $c.dir }
        $name = $(if ($cwd.TrimEnd('\') -eq $userHome) { '~' } else { Split-Path -Leaf $cwd.TrimEnd('\') })
        if (-not $name) { $name = $cwd }
        $r.paths[$name] = $cwd
        foreach ($h in $c.w.Keys) {
            if ($h -lt $first) { continue }
            $r.total[$name] = [double]$r.total[$name] + $c.w[$h]
            if (-not $r.hours[$h]) { $r.hours[$h] = @{} }
            $r.hours[$h][$name] = [double]$r.hours[$h][$name] + $c.w[$h]
        }
    }
    return $r
}

function Start-HistoryJob([string]$kind) {
    if ($script:HistJob) { return }
    $ps = [powershell]::Create()
    $since = Get-UnixMinute ((Get-Date).AddDays(-7))
    $projects = Join-Path $env:USERPROFILE '.claude\projects'
    if ($kind -eq 'backfill') {
        $dir = Join-Path $projects ($script:Root -replace '[^A-Za-z0-9]', '-')
        [void]$ps.AddScript($HistBackfill.ToString()).AddArgument($dir).AddArgument($since)
    } else {
        $script:ProjTry = Get-Date
        [void]$ps.AddScript($ProjScan.ToString()).AddArgument($projects).AddArgument($script:ProjCache).AddArgument($since)
    }
    $script:HistJob = @{ ps = $ps; handle = $ps.BeginInvoke(); kind = $kind }
}

function Collect-HistoryJob {
    $job = $script:HistJob
    if (-not $job -or -not $job.handle.IsCompleted) { return }
    $script:HistJob = $null
    try {
        $out = $job.ps.EndInvoke($job.handle)
        if ($job.ps.Streams.Error.Count) { throw $job.ps.Streams.Error[0].Exception }
        if ($job.kind -eq 'backfill') {
            # Older than anything sampled so far, one per step unless the value changes.
            $have = $script:Hist.samples
            $stop = $(if ($have.Count) { $have[0][0] } else { [int]::MaxValue })
            $add = New-Object System.Collections.ArrayList
            foreach ($s in @($out[0] | Sort-Object { $_[0] })) {
                if ($s[0] -ge $stop) { break }
                if ($add.Count) {
                    $last = $add[$add.Count - 1]
                    if ($last[1] -eq $s[1] -and $last[2] -eq $s[2] -and $s[0] - $last[0] -lt $HistStepMinutes) { continue }
                }
                [void]$add.Add($s)
            }
            if ($add.Count) { $have.InsertRange(0, $add) }
            $script:Hist.backfilled = $true
            Save-History
        } else {
            $script:Proj   = $out[0]
            $script:ProjAt = Get-Date
        }
        $script:HistKey = $null
    } catch {
        # A failed backfill is not tried again - the history simply starts from now.
        if ($job.kind -eq 'backfill') { $script:Hist.backfilled = $true; Save-History }
        try {
            "$(Get-Date -Format s)`thistory: $($_.Exception.Message)" |
                Out-File (Join-Path $script:Root 'widget-error.log') -Append -Encoding utf8
        } catch {}
    } finally {
        $job.ps.Dispose()
    }
}

# Colors of the two lines: the session bar's green and the week bar's blue.
$HistColors = @{ session = '#FF4ADE80'; area = '#264ADE80'; week = '#FF60A5FA' }

function Set-HistLegend {
    $c = $UI.HistCaption
    $c.Inlines.Clear()
    if (-not $script:Hist.samples.Count) { $c.Text = T 'hist.empty'; return }
    foreach ($p in @(@('session', 'hist.session'), @('week', 'hist.week'))) {
        $mark = New-Object System.Windows.Documents.Run ([string][char]0x2501 + ' ')
        $mark.Foreground = New-Brush $HistColors[$p[0]]
        $c.Inlines.Add($mark)
        $c.Inlines.Add((New-Object System.Windows.Documents.Run ((T $p[1]) + '    ')))
    }
}

function Draw-HistoryChart {
    $cv = $UI.HistChart
    $cv.Children.Clear()
    $UI.HistDays.Children.Clear()
    $W = $BarWidth; $H = $HistChartHeight
    $t1 = Get-UnixMinute (Get-Date)
    $t0 = $t1 - 7 * 1440
    $script:HistRange = @($t0, $t1)

    # Midnights and weekday names under each day.
    $day = (ConvertFrom-UnixMinute $t0).Date.AddDays(1)
    $prevX = 0.0
    while ($true) {
        $x = $(if ($day -lt (Get-Date)) { $W * ((Get-UnixMinute $day) - $t0) / ($t1 - $t0) } else { $W })
        $name = $day.AddDays(-1).ToString('ddd', (Get-LangCulture))
        if ($x - $prevX -ge 14) {
            $tb = New-Object System.Windows.Controls.TextBlock
            $tb.Text = $name; $tb.FontFamily = 'Segoe UI'; $tb.FontSize = 8
            $tb.Foreground = New-Brush '#FF52525B'; $tb.Width = $x - $prevX; $tb.TextAlignment = 'Center'
            [System.Windows.Controls.Canvas]::SetLeft($tb, $prevX)
            [void]$UI.HistDays.Children.Add($tb)
        }
        if ($day -ge (Get-Date)) { break }
        $ln = New-Object System.Windows.Shapes.Line
        $ln.X1 = $x; $ln.X2 = $x; $ln.Y1 = 0; $ln.Y2 = $H
        $ln.Stroke = New-Brush '#1AFFFFFF'; $ln.StrokeThickness = 1
        [void]$cv.Children.Add($ln)
        $prevX = $x
        $day = $day.AddDays(1)
    }

    # Runs of samples without gaps; each becomes a figure of its own.
    foreach ($col in @(@(2, 'week'), @(1, 'session'))) {
        $line = New-Object System.Text.StringBuilder
        $area = New-Object System.Text.StringBuilder
        $run = New-Object System.Collections.ArrayList
        $flush = {
            if ($run.Count -ge 1) {
                $pts = @($run | ForEach-Object { (Format-Coord $_[0]) + ',' + (Format-Coord $_[1]) })
                if ($run.Count -eq 1) { $pts += (Format-Coord ($run[0][0] + 1)) + ',' + (Format-Coord $run[0][1]) }
                [void]$line.Append('M' + ($pts -join ' L') + ' ')
                [void]$area.Append('M' + (Format-Coord $run[0][0]) + ',' + (Format-Coord $H) + ' L' + ($pts -join ' L') +
                                   ' L' + (Format-Coord ($run[$run.Count - 1][0] + $(if ($run.Count -eq 1) { 1 } else { 0 }))) + ',' + (Format-Coord $H) + ' Z ')
            }
        }
        $prevT = $null
        foreach ($s in $script:Hist.samples) {
            if ($s[0] -lt $t0) { continue }
            $v = $s[$col[0]]
            if ($v -lt 0 -or ($null -ne $prevT -and $s[0] - $prevT -gt $HistGapMinutes)) { . $flush; $run.Clear() }
            $prevT = $s[0]
            if ($v -ge 0) { [void]$run.Add(@(($W * ($s[0] - $t0) / ($t1 - $t0)), (1 + ($H - 2) * (1 - [math]::Min(100, $v) / 100.0)))) }
        }
        . $flush
        if (-not $line.Length) { continue }
        if ($col[1] -eq 'session') {
            $fill = New-Object System.Windows.Shapes.Path
            $fill.Data = [System.Windows.Media.Geometry]::Parse($area.ToString())
            $fill.Fill = New-Brush $HistColors.area
            [void]$cv.Children.Add($fill)
        }
        $path = New-Object System.Windows.Shapes.Path
        $path.Data = [System.Windows.Media.Geometry]::Parse($line.ToString())
        $path.Stroke = New-Brush $HistColors[$col[1]]
        $path.StrokeThickness = 1.2
        $path.StrokeLineJoin = 'Round'
        [void]$cv.Children.Add($path)
    }

    $script:HistCursor = New-Object System.Windows.Shapes.Line
    $script:HistCursor.Y1 = 0; $script:HistCursor.Y2 = $H
    $script:HistCursor.Stroke = New-Brush '#66FFFFFF'; $script:HistCursor.StrokeThickness = 1
    $script:HistCursor.Visibility = 'Collapsed'
    [void]$cv.Children.Add($script:HistCursor)
    Set-HistLegend
}

# The point under the mouse: time, both percentages and the busiest project of that hour.
function Show-HistPoint([double]$x) {
    if (-not $script:HistRange) { return }
    $t0 = $script:HistRange[0]; $t1 = $script:HistRange[1]
    $x = [math]::Max(0, [math]::Min($BarWidth, $x))
    $t = [int]($t0 + ($t1 - $t0) * $x / $BarWidth)
    $script:HistCursor.X1 = $x; $script:HistCursor.X2 = $x
    $script:HistCursor.Visibility = 'Visible'

    # Nearest sample at or before the cursor: the samples are in time order.
    $a = $script:Hist.samples
    $lo = 0; $hi = $a.Count - 1; $hit = $null
    while ($lo -le $hi) {
        $mid = [int][math]::Floor(($lo + $hi) / 2)
        if ($a[$mid][0] -le $t) { $hit = $a[$mid]; $lo = $mid + 1 } else { $hi = $mid - 1 }
    }
    $at = ConvertFrom-UnixMinute $t
    $parts = @($at.ToString('ddd HH:mm', (Get-LangCulture)))
    if ($hit -and $t - $hit[0] -le $HistGapMinutes) {
        if ($hit[1] -ge 0) { $parts += '{0} {1}%' -f (T 'hist.session'), $hit[1] }
        if ($hit[2] -ge 0) { $parts += '{0} {1}%' -f (T 'hist.week'), $hit[2] }
    } else {
        $parts += T 'noData'
    }
    if ($script:Proj) {
        $byName = $script:Proj.hours[[int][math]::Floor($t / 60)]
        if ($byName -and $byName.Count) {
            $parts += ($byName.GetEnumerator() | Sort-Object Value -Descending | Select-Object -First 1).Key
        }
    }
    $UI.HistCaption.Text = $parts -join '  ·  '
}

function Show-Projects {
    $rows = $UI.ProjRows
    $rows.Children.Clear()
    $p = $script:Proj
    if (-not $p) {
        $tb = New-Object System.Windows.Controls.TextBlock
        $tb.Text = T 'hist.counting'; $tb.FontFamily = 'Segoe UI'; $tb.FontSize = 10
        $tb.Foreground = New-Brush '#FF6B7280'
        [void]$rows.Children.Add($tb)
        return
    }
    $sum = 0.0
    foreach ($v in $p.total.Values) { $sum += $v }
    if ($sum -le 0) { $UI.ProjPanel.Visibility = 'Collapsed'; return }
    $UI.ProjPanel.Visibility = 'Visible'
    $top = @($p.total.GetEnumerator() | Sort-Object Value -Descending | Select-Object -First 4)
    foreach ($e in $top) {
        $share = 100.0 * $e.Value / $sum
        $g = New-Object System.Windows.Controls.Grid
        $g.Margin = New-Object System.Windows.Thickness 0, 0, 0, 2
        $g.Background = [System.Windows.Media.Brushes]::Transparent
        $g.ToolTip = $p.paths[$e.Key]
        foreach ($w in @('*', '70', '34')) {
            $cd = New-Object System.Windows.Controls.ColumnDefinition
            $cd.Width = $(if ($w -eq '*') { New-Object System.Windows.GridLength(1, 'Star') } else { New-Object System.Windows.GridLength([double]$w) })
            $g.ColumnDefinitions.Add($cd)
        }
        $name = New-Object System.Windows.Controls.TextBlock
        $name.Text = $e.Key; $name.FontFamily = 'Segoe UI'; $name.FontSize = 10
        $name.Foreground = New-Brush '#FFD4D4D8'; $name.TextTrimming = 'CharacterEllipsis'
        $name.Margin = New-Object System.Windows.Thickness 0, 0, 8, 0
        $bg = New-Object System.Windows.Controls.Border
        $bg.Background = New-Brush '#26FFFFFF'; $bg.CornerRadius = New-Object System.Windows.CornerRadius 2; $bg.Height = 4; $bg.VerticalAlignment = 'Center'
        [System.Windows.Controls.Grid]::SetColumn($bg, 1)
        $bar = New-Object System.Windows.Controls.Border
        $bar.Background = New-Brush '#FFD77757'; $bar.CornerRadius = New-Object System.Windows.CornerRadius 2; $bar.HorizontalAlignment = 'Left'
        $bar.Width = [math]::Max(2, 70 * $share / 100)
        $bg.Child = $bar
        $pct = New-Object System.Windows.Controls.TextBlock
        $pct.Text = '{0:0}%' -f $share; $pct.FontFamily = 'Segoe UI'; $pct.FontSize = 10
        $pct.Foreground = New-Brush '#FF8B8B94'; $pct.TextAlignment = 'Right'
        [System.Windows.Controls.Grid]::SetColumn($pct, 2)
        foreach ($el in @($name, $bg, $pct)) { [void]$g.Children.Add($el) }
        [void]$rows.Children.Add($g)
    }
}

function Update-History {
    Collect-HistoryJob
    if (-not $script:Cfg.showHistory) { $UI.HistPanel.Visibility = 'Collapsed'; return }
    $UI.HistPanel.Visibility = 'Visible'
    if (-not $script:Hist.backfilled) { Start-HistoryJob 'backfill' }
    if ($UI.Details.Visibility -ne 'Visible') { return }
    if (([datetime]::Now - $script:ProjTry).TotalMinutes -ge $ProjScanMinutes) { Start-HistoryJob 'projects' }
    # Redrawn when there is something new, and every ten minutes as the week slides on.
    $n = $script:Hist.samples.Count
    $now = Get-Date
    $key = '{0}|{1}|{2}|{3}|{4}{5}' -f (Get-Lang), $n, $(if ($n) { $script:Hist.samples[$n - 1][0] }),
           $script:ProjAt, $now.ToString('yyyyMMddHH'), [math]::Floor($now.Minute / 10)
    if ($key -eq $script:HistKey) { return }
    $script:HistKey = $key
    Draw-HistoryChart
    Show-Projects
}

$UI.HistChart.add_MouseMove({
    param($s, $e)
    Show-HistPoint $e.GetPosition($UI.HistChart).X
})
$UI.HistChart.add_MouseLeave({
    if ($script:HistCursor) { $script:HistCursor.Visibility = 'Collapsed' }
    Set-HistLegend
})
