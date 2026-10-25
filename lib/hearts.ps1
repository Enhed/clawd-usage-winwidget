# ----- hearts: tamagotchi-style health = how much of the main limit is left -----
# Three hearts with halves: every ~16.7% of what is left is one half. Zero hearts
# only at 100%, exactly when Clawd lies down legs up.

$HeartPx   = 1.4
$HeartRows = @('.##.##.', '#######', '#######', '.#####.', '..###..', '...#...')
$HeartOn   = '#FFF87171'
$HeartOff  = '#FF3F3F46'

function New-HeartGeo([int]$maxCol) {
    $gg = New-Object System.Windows.Media.GeometryGroup
    for ($y = 0; $y -lt $HeartRows.Count; $y++) {
        for ($x = 0; $x -le $maxCol; $x++) {
            if ($HeartRows[$y][$x] -ne '#') { continue }
            $gg.Children.Add([System.Windows.Media.RectangleGeometry]::new(
                [System.Windows.Rect]::new($x * $HeartPx, $y * $HeartPx, $HeartPx, $HeartPx)))
        }
    }
    $gg.Freeze()
    return $gg
}
$HeartFull = New-HeartGeo 6
$HeartHalf = New-HeartGeo 3

$script:HeartUi = @()
for ($i = 0; $i -lt 3; $i++) {
    $cell = New-Object System.Windows.Controls.Grid
    if ($i -lt 2) { $cell.Margin = '0,0,2.5,0' }
    $cell.RenderTransformOrigin = '0.5,0.5'
    $cell.RenderTransform = New-Object System.Windows.Media.ScaleTransform 1, 1
    $back  = New-Object System.Windows.Shapes.Path
    $back.Data = $HeartFull
    $back.Fill = New-Brush $HeartOff
    $front = New-Object System.Windows.Shapes.Path
    $front.Fill = New-Brush $HeartOn
    $cell.Children.Add($back)  | Out-Null
    $cell.Children.Add($front) | Out-Null
    $UI.Hearts.Children.Add($cell) | Out-Null
    $script:HeartUi += @{ cell = $cell; front = $front }
}
$UI.MascotLove.Data = $HeartFull

# Demo "losing hearts": one half every DrainStep ticks, then lies down.
$DrainStep = 22
$DrainLen  = 6 * $DrainStep + 35

# Health by number of heart halves. Applies on top of any mode: walking
# speed, tired eyes, yawns, sweat, swaying and stumbling. 0 - lies down (dead mode).
# Level name - T "health.<number of halves>".
$HealthTiers = @{
    6 = @{ speed = 1.25; hop = 300 }
    5 = @{ speed = 1.0 }
    4 = @{ speed = 0.9;  yawn = 350 }
    3 = @{ speed = 0.75; yawn = 200; eyes = 'focus' }
    2 = @{ speed = 0.55; yawn = 160; eyes = 'focus'; sweat = $true }
    1 = @{ speed = 0.35; eyes = 'blink'; sweat = $true; stagger = $true; stumble = 220 }
    0 = @{ speed = 0.0 }
}

# How many heart halves to show: 0..6, or $null if there is no data.
function Get-Halves {
    $m = $script:Mz
    $halves = $null
    if ($null -ne $m.forceHearts)  { $halves = [int]$m.forceHearts }
    elseif ($m.force -eq 'dead')   { $halves = 0 }
    elseif ($null -ne $m.pct) {
        $halves = [int][math]::Ceiling([math]::Max(0, 100 - $m.pct) * 6 / 100.0)
    }
    if ($null -eq $halves) { return $null }
    return [int][math]::Min(6, [math]::Max(0, $halves))
}

function Step-Hearts {
    $m = $script:Mz
    $halves = Get-Halves
    if ($null -eq $halves) {
        $UI.Hearts.Visibility = 'Collapsed'
        $m.halves = $null
        return
    }
    $UI.Hearts.Visibility = 'Visible'
    $tip = T "health.$halves"
    if ($null -ne $m.pct -and $null -eq $m.forceHearts) {
        $tip = (T $(if ($m.limit -eq 'week') { 'hearts.leftWeek' } else { 'hearts.left' })) -f $tip, (100 - $m.pct)
    }
    if ($UI.Hearts.ToolTip -ne $tip) { $UI.Hearts.ToolTip = $tip }

    # Lost a heart - the lost part blinks for a couple of seconds.
    if ($null -ne $m.halves -and $halves -lt $m.halves) { $m.lostT = 0; $m.lostFrom = $m.halves }
    $m.halves = $halves
    $show = $halves
    if ($m.lostT -ge 0) {
        if ($m.lostT % 4 -lt 2) { $show = $m.lostFrom }
        $m.lostT++
        if ($m.lostT -ge 16) { $m.lostT = -1 }
    }

    if ("$show" -ne $m.heartsKey) {
        $m.heartsKey = "$show"
        for ($i = 0; $i -lt 3; $i++) {
            $h = $show - 2 * $i
            $script:HeartUi[$i].front.Data =$(if ($h -ge 2) { $HeartFull } elseif ($h -eq 1) { $HeartHalf } else { $null })
        }
    }

    # Last bit of health left - the hearts beat.
    $beat = 1.0
    if ($halves -gt 0 -and $halves -le 2) {
        $p = $m.tick % 12
        if ($p -eq 0) { $beat = 1.3 } elseif ($p -eq 1) { $beat = 1.15 }
    }
    foreach ($hu in $script:HeartUi) {
        $hu.cell.RenderTransform.ScaleX = $beat
        $hu.cell.RenderTransform.ScaleY = $beat
    }
}
