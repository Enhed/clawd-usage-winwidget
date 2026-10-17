# ----- palette -----

function ConvertTo-Color([string]$hex) { return [System.Windows.Media.ColorConverter]::ConvertFromString($hex) }

function Mix-Color($a, $b, [double]$k) {
    if ($k -lt 0) { $k = 0 } elseif ($k -gt 1) { $k = 1 }
    return [System.Windows.Media.Color]::FromArgb(
        [byte]($a.A + ($b.A - $a.A) * $k), [byte]($a.R + ($b.R - $a.R) * $k),
        [byte]($a.G + ($b.G - $a.G) * $k), [byte]($a.B + ($b.B - $a.B) * $k))
}

# Cloudiness: the color fades toward gray and darkens.
function Dim-Color($c, [double]$g) {
    $l = 0.3 * $c.R + 0.59 * $c.G + 0.11 * $c.B
    $f = 1 - 0.3 * $g
    return [System.Windows.Media.Color]::FromArgb($c.A,
        [byte](($c.R + ($l - $c.R) * $g) * $f), [byte](($c.G + ($l - $c.G) * $g) * $f),
        [byte](($c.B + ($l - $c.B) * $g) * $f))
}

$SkyPal = @{
    night = @{ top = (ConvertTo-Color '#00304A8C'); bottom = (ConvertTo-Color '#1A304A8C'); light = 0.0 }
    dawn  = @{ top = (ConvertTo-Color '#00404E8A'); bottom = (ConvertTo-Color '#33E08A66'); light = 0.5 }
    day   = @{ top = (ConvertTo-Color '#004A8CCB'); bottom = (ConvertTo-Color '#2E6FA8D8'); light = 1.0 }
    dusk  = @{ top = (ConvertTo-Color '#00383070'); bottom = (ConvertTo-Color '#33D86A50'); light = 0.5 }
}
$SkyPhases = @('dawn', 'day', 'dusk', 'night')   # names - T "phase.<id>"
$SkyCol = @{
    sunHigh = (ConvertTo-Color '#FFFDE68A'); sunLow = (ConvertTo-Color '#FFFB923C')
    snowDay  = (ConvertTo-Color '#80DDE4EC'); snowNight  = (ConvertTo-Color '#50A1A8B5')
    cloudDay = (ConvertTo-Color '#FFB4B4BC'); cloudNight = (ConvertTo-Color '#FF5E5E68')
    cloudRain = (ConvertTo-Color '#FF52525B')
}

# ----- sprites -----

function New-PixelGeo([string[]]$rows, [double]$px, [char]$on = '#') {
    $gg = New-Object System.Windows.Media.GeometryGroup
    for ($y = 0; $y -lt $rows.Count; $y++) {
        $x = 0
        while ($x -lt $rows[$y].Length) {
            if ($rows[$y][$x] -ne $on) { $x++; continue }
            $x0 = $x
            while ($x -lt $rows[$y].Length -and $rows[$y][$x] -eq $on) { $x++ }
            $gg.Children.Add([System.Windows.Media.RectangleGeometry]::new(
                [System.Windows.Rect]::new($x0 * $px, $y * $px, ($x - $x0) * $px, $px)))
        }
    }
    $gg.Freeze()
    return $gg
}

function New-SkyShape([string]$kind, [double]$w, [double]$h, $fill) {
    $s = New-Object "System.Windows.Shapes.$kind"
    if ($w) { $s.Width = $w; $s.Height = $h }
    if ($fill) { $s.Fill = $(if ($fill -is [string]) { New-Brush $fill } else { $fill }) }
    $s.Visibility = 'Collapsed'
    $UI.SkyFx.Children.Add($s) | Out-Null
    return $s
}

$SkyBrush = New-Object System.Windows.Media.LinearGradientBrush
$SkyBrush.StartPoint = '0,0'; $SkyBrush.EndPoint = '0,1'
$SkyBrush.GradientStops.Add((New-Object System.Windows.Media.GradientStop ($SkyPal.night.top), 0))
$SkyBrush.GradientStops.Add((New-Object System.Windows.Media.GradientStop ($SkyPal.night.bottom), 1))
$UI.Sky.Background = $SkyBrush

$script:Sky = @{
    force = $null; forceWx = $null; key = ''; w = 0; h = 0; flash = 0; moonKey = ''
    light = 0.0; kind = $null; starOp = 0.0; clouds = 0; rain = 0; snow = 0; tick = 0; broken = $false
}
$script:WxPlace = $null

$script:Stars = @()
for ($i = 0; $i -lt 20; $i++) {
    $script:Stars += @{ r = (New-SkyShape Rectangle 1.2 1.2 '#FFF8FAFC'); fx = $script:Rnd.NextDouble(); fy = $script:Rnd.NextDouble() * 0.6 }
}

$MoonPx   = 1.3
$MoonDark = New-SkyShape Path 0 0 '#2EE5E7EB'
$MoonLit  = New-SkyShape Path 0 0 '#FFF1F5F9'
$SunGlow  = New-SkyShape Ellipse 20 20 $null
$SunGlow.Fill = New-Object System.Windows.Media.RadialGradientBrush (
    (ConvertTo-Color '#40FDE68A'), (ConvertTo-Color '#00FDE68A'))
$SunBody  = New-SkyShape Path 0 0 $null
$SunBody.Data = New-PixelGeo @('..###..', '.#####.', '#######', '#######', '#######', '.#####.', '..###..') 1.4
$SunBrush = New-Object System.Windows.Media.SolidColorBrush $SkyCol.sunHigh
$SunBody.Fill = $SunBrush

$CloudShapes = @(
    , @('....###.....', '..#######...', '.##########.', '############')
    , @('..###...', '.######.', '########')
    , @('...##.##..', '.########.', '##########')
)
$CloudBrush = New-Object System.Windows.Media.SolidColorBrush $SkyCol.cloudDay
$script:Clouds = @()
for ($i = 0; $i -lt 9; $i++) {
    $rows = $CloudShapes[$i % $CloudShapes.Count]
    $p = New-SkyShape Path 0 0 $CloudBrush
    $p.Data = New-PixelGeo $rows 2
    $script:Clouds += @{
        p = $p; w = $rows[0].Length * 2; x = -1.0; fy = 0.05 + 0.3 * $script:Rnd.NextDouble()
        v = 0.7 + 0.6 * $script:Rnd.NextDouble(); fade = 0.0
    }
}

# Fog bands with blurred edges so they do not read as rectangles.
$FogBrush = New-Object System.Windows.Media.LinearGradientBrush
$FogBrush.StartPoint = '0,0'; $FogBrush.EndPoint = '1,0'
foreach ($fs in @(@('#00E5E7EB', 0), @('#FFE5E7EB', 0.5), @('#00E5E7EB', 1))) {
    $FogBrush.GradientStops.Add((New-Object System.Windows.Media.GradientStop (ConvertTo-Color $fs[0]), $fs[1]))
}
$script:Fog = @()
for ($i = 0; $i -lt 3; $i++) {
    $script:Fog += @{ r = (New-SkyShape Rectangle 10 3 $FogBrush); x = $script:Rnd.NextDouble(); fy = 0.42 + 0.2 * $i }
}

$script:Drops = @()
for ($i = 0; $i -lt 40; $i++) {
    $script:Drops += @{ r = (New-SkyShape Rectangle 1 3.5 '#8093C5FD'); x = 0.0; y = -99.0; v = 0.0 }
}
$script:Flakes = @()
for ($i = 0; $i -lt 34; $i++) {
    $script:Flakes += @{ r = (New-SkyShape Rectangle 1.6 1.6 '#C0E4E4E7'); x = 0.0; y = -99.0; v = 0.0; ph = 0.0 }
}

$GroundBrush = New-Object System.Windows.Media.SolidColorBrush $SkyCol.snowNight
$Ground = New-SkyShape Rectangle 10 1.5 $GroundBrush
$Flash  = New-SkyShape Rectangle 10 10 '#FFF8FAFC'

# Moon phase from how far the Moon is from the Sun along the ecliptic, with the
# main periodic terms (low-precision formulas, good to about an hour). The mean
# synodic month alone is off by up to a day - fine for the picture, not for "% lit".
$MoonMonth = 29.530588853
function Get-MoonAge {
    $d   = ([datetime]::UtcNow - [datetime]::new(2000, 1, 1, 12, 0, 0, [System.DateTimeKind]::Utc)).TotalDays
    $rad = [math]::PI / 180
    $g   = (357.528 + 0.9856003 * $d) * $rad                       # Sun's mean anomaly
    $sun = 280.460 + 0.9856474 * $d + 1.915 * [math]::Sin($g) + 0.020 * [math]::Sin(2 * $g)
    $Lm  = 218.316 + 13.176396 * $d                                # Moon's mean longitude
    $Mm  = (134.963 + 13.064993 * $d) * $rad                       # and mean anomaly
    $D   = ($Lm - (280.460 + 0.9856474 * $d)) * $rad               # mean elongation
    $moon = $Lm + 6.289 * [math]::Sin($Mm) - 1.274 * [math]::Sin(2 * $D - $Mm) + 0.658 * [math]::Sin(2 * $D) -
            0.186 * [math]::Sin($g) - 0.059 * [math]::Sin(2 * $D - 2 * $Mm) - 0.057 * [math]::Sin(2 * $D - $Mm - $g)
    $e = ((($moon - $sun) % 360) + 360) % 360
    return $e / 360 * $MoonMonth
}

# For the sky's tooltip: @{ name = 0..7 from new moon round to waning crescent; lit = percent }.
function Get-MoonInfo {
    $f = (Get-MoonAge) / $MoonMonth
    return @{ name = [int][math]::Floor($f * 8 + 0.5) % 8
              lit  = [int][math]::Round((1 - [math]::Cos(2 * [math]::PI * $f)) / 2 * 100) }
}

# A pixel is lit if it is on the bright side of the terminator u = cos(θ)·√(1-v²).
function Set-MoonPhase([double]$lat) {
    $P   = $MoonMonth
    $age = Get-MoonAge
    $key = "$([math]::Round($age * 2))|$($lat -lt 0)"
    if ($key -eq $script:Sky.moonKey) { return }
    $script:Sky.moonKey = $key
    $th = 2 * [math]::PI * $age / $P
    $k  = [math]::Cos($th)
    $n  = 7; $r = $n / 2.0
    $lit = @(); $dark = @()
    for ($y = 0; $y -lt $n; $y++) {
        $a = ''; $b = ''
        for ($x = 0; $x -lt $n; $x++) {
            $u = ($x + 0.5 - $r) / $r; $v = ($y + 0.5 - $r) / $r
            if ($lat -lt 0) { $u = -$u }   # in the southern hemisphere the waxing moon is on the left
            $in = ($u * $u + $v * $v) -le 1.05
            $t  = $k * [math]::Sqrt([math]::Max(0, 1 - $v * $v))
            $on = $in -and $(if ($th -lt [math]::PI) { $u -gt $t } else { $u -lt -$t })
            $a += $(if ($on) { '#' } else { '.' })
            $b += $(if ($in -and -not $on) { '#' } else { '.' })
        }
        $lit += $a; $dark += $b
    }
    $MoonLit.Data  = New-PixelGeo $lit  $MoonPx
    $MoonDark.Data = New-PixelGeo $dark $MoonPx
}

# Position of a celestial body on the arc: p 0..1 from horizon to horizon.
function Set-OnArc($el, [double]$p, [double]$half) {
    $s = $script:Sky
    if ($p -lt -0.06 -or $p -gt 1.06) { $el.Visibility = 'Collapsed'; return $false }
    $alt = [math]::Sin([math]::PI * $p)
    [System.Windows.Controls.Canvas]::SetLeft($el, 7 + $p * ($s.w - 14) - $half)
    [System.Windows.Controls.Canvas]::SetTop($el, $s.h + 3 - $alt * ($s.h - 12) - $half)
    $el.Visibility = 'Visible'
    return $true
}

function Step-Sky {
    $s = $script:Sky
    $s.tick++
    $w = $UI.Sky.ActualWidth; $h = $UI.Sky.ActualHeight
    if ($w -le 0 -or $h -le 0) { return }

    # Size changed - lay out the static parts again.
    if ($w -ne $s.w -or $h -ne $s.h) {
        $s.w = $w; $s.h = $h; $s.key = ''
        foreach ($st in $script:Stars) {
            [System.Windows.Controls.Canvas]::SetLeft($st.r, [math]::Round($st.fx * ($w - 2)))
            [System.Windows.Controls.Canvas]::SetTop($st.r, [math]::Round(2 + $st.fy * $h))
        }
        foreach ($c in $script:Clouds) { if ($c.x -lt 0) { $c.x = $script:Rnd.NextDouble() * $w } }
        foreach ($fg in $script:Fog) { $fg.r.Width = $w * 0.6 }
        $Ground.Width = $w
        [System.Windows.Controls.Canvas]::SetTop($Ground, $h - 1.5)
        $Flash.Width = $w; $Flash.Height = $h
    }

    $st  = Get-SunTimes
    $sr  = $st.sr; $ss = $st.ss
    $t   = (Get-Date).TimeOfDay.TotalMinutes
    switch ($s.force) {
        'dawn'  { $t = $sr - 10 }
        'day'   { $t = ($sr + $ss) / 2 }
        'dusk'  { $t = $ss + 10 }
        'night' { $t = 0 }
    }
    $wx   = Get-SkyWeather
    $code = $(if ($wx) { [int]$wx.code } else { 0 })
    $wind = $(if ($wx) { [double]$wx.wind } else { 8.0 })

    # Recompute colors once a minute or when the weather changes.
    $key = "$([int]$t)|$code|$w|$h"
    if ($key -ne $s.key) {
        $s.key  = $key
        $kind   = Get-WeatherKind $code
        $s.kind = $kind
        $stops  = @(
            @(($sr - 80), 'night'), @(($sr - 10), 'dawn'), @(($sr + 70), 'day'),
            @(($ss - 70), 'day'), @(($ss + 10), 'dusk'), @(($ss + 80), 'night')
        )
        $a = $SkyPal.night; $b = $SkyPal.night; $k = 0.0
        for ($i = 0; $i -lt $stops.Count - 1; $i++) {
            if ($t -ge $stops[$i][0] -and $t -lt $stops[$i + 1][0]) {
                $a = $SkyPal[$stops[$i][1]]; $b = $SkyPal[$stops[$i + 1][1]]
                $k = ($t - $stops[$i][0]) / ($stops[$i + 1][0] - $stops[$i][0])
                break
            }
        }
        $s.light = $a.light + ($b.light - $a.light) * $k
        $g = $kind.cover * 0.9
        $SkyBrush.GradientStops[0].Color = Dim-Color (Mix-Color $a.top $b.top $k) $g
        $SkyBrush.GradientStops[1].Color = Dim-Color (Mix-Color $a.bottom $b.bottom $k) $g

        # Snow has settled - a thin white strip underfoot.
        $Ground.Visibility = $(if ($kind.snow -gt 0) { 'Visible' } else { 'Collapsed' })
        $GroundBrush.Color = Mix-Color $SkyCol.snowNight $SkyCol.snowDay $s.light
        $cc = Mix-Color $SkyCol.cloudNight $SkyCol.cloudDay $s.light
        if ($kind.rain -or $kind.storm) { $cc = Mix-Color $cc $SkyCol.cloudRain 0.55 }
        $CloudBrush.Color = $cc

        # Sun: by day along the arc from sunrise to sunset, orange near the horizon.
        $vis = [math]::Max(0, 1 - $kind.cover * 1.15)
        $p = ($t - $sr) / ($ss - $sr)
        $SunBody.Opacity = $vis; $SunGlow.Opacity = $vis
        if ((Set-OnArc $SunBody $p 4.9) -and $vis -gt 0) {
            Set-OnArc $SunGlow $p 10 | Out-Null
            $SunBrush.Color = Mix-Color $SkyCol.sunLow $SkyCol.sunHigh ([math]::Sin([math]::PI * $p) * 1.6)
        } else {
            $SunBody.Visibility = 'Collapsed'; $SunGlow.Visibility = 'Collapsed'
        }
        # Moon: at night, from sunset to the next sunrise.
        $place = Get-WeatherPlace
        Set-MoonPhase $(if ($place) { $place.lat } else { 50 })
        $q = (($t - $ss + 1440) % 1440) / ($sr + 1440 - $ss)
        $MoonLit.Opacity = $vis; $MoonDark.Opacity = $vis
        if (-not (Set-OnArc $MoonLit $q 4.55) -or $vis -le 0) { $MoonLit.Visibility = 'Collapsed'; $MoonDark.Visibility = 'Collapsed' }
        else { Set-OnArc $MoonDark $q 4.55 | Out-Null }

        $s.starOp = (1 - $s.light * 2) * [math]::Max(0, 1 - $kind.cover * 1.4)
        # Weather counts are tuned for a ~140px strip; a wider sky gets more.
        $dens = [math]::Max(1.0, $w / 140.0)
        $s.clouds = [math]::Min($script:Clouds.Count, [int][math]::Round($kind.cover * 5 * $dens))
        $s.rain   = [math]::Min($script:Drops.Count,  [int][math]::Round($kind.rain * $dens))
        $s.snow   = [math]::Min($script:Flakes.Count, [int][math]::Round($kind.snow * $dens))
    }
    $kind = $s.kind

    # Stars twinkle.
    for ($i = 0; $i -lt $script:Stars.Count; $i++) {
        $r = $script:Stars[$i].r
        if ($s.starOp -le 0) { $r.Visibility = 'Collapsed'; continue }
        $r.Visibility = 'Visible'
        $r.Opacity = $s.starOp * (0.55 + 0.45 * [math]::Sin($s.tick / 7.0 + $i * 1.7))
    }

    # Clouds drift with the wind, extra ones fade out, needed ones fade in.
    $drift = 0.04 + $wind / 350.0
    for ($i = 0; $i -lt $script:Clouds.Count; $i++) {
        $c = $script:Clouds[$i]
        $want = $(if ($i -lt $s.clouds) { 1.0 } else { 0.0 })
        $c.fade += [math]::Max(-0.03, [math]::Min(0.03, $want - $c.fade))
        if ($c.fade -le 0) { $c.p.Visibility = 'Collapsed'; continue }
        $c.x += $drift * $c.v
        if ($c.x -gt $w) { $c.x = -$c.w; $c.fy = 0.05 + 0.3 * $script:Rnd.NextDouble() }
        $c.p.Visibility = 'Visible'
        $c.p.Opacity = 0.65 * $c.fade
        [System.Windows.Controls.Canvas]::SetLeft($c.p, [math]::Round($c.x))
        [System.Windows.Controls.Canvas]::SetTop($c.p, [math]::Round($c.fy * $h))
    }

    # Fog - translucent bands, crawling slowly.
    foreach ($fg in $script:Fog) {
        if (-not $kind.fog) { $fg.r.Visibility = 'Collapsed'; continue }
        $fg.x = ($fg.x + 0.0015) % 1.6
        $fg.r.Visibility = 'Visible'
        $fg.r.Opacity = 0.14 + 0.05 * [math]::Sin($s.tick / 20.0 + $fg.fy * 10)
        [System.Windows.Controls.Canvas]::SetLeft($fg.r, ($fg.x - 0.6) * $w)
        [System.Windows.Controls.Canvas]::SetTop($fg.r, $fg.fy * $h)
    }

    # Rain slants with the wind.
    $slant = [math]::Min(1.2, $wind / 25.0)
    for ($i = 0; $i -lt $script:Drops.Count; $i++) {
        $d = $script:Drops[$i]
        if ($i -ge $s.rain) { $d.r.Visibility = 'Collapsed'; $d.y = -99; continue }
        if ($d.y -lt -50 -or $d.y -gt $h) {
            $d.x = $script:Rnd.NextDouble() * ($w + 10) - 10
            $d.y = $(if ($d.y -lt -50) { $script:Rnd.NextDouble() * $h } else { -4 })
            $d.v = 3.5 + 1.5 * $script:Rnd.NextDouble()
        }
        $d.y += $d.v; $d.x += $slant
        $d.r.Visibility = 'Visible'
        [System.Windows.Controls.Canvas]::SetLeft($d.r, $d.x)
        [System.Windows.Controls.Canvas]::SetTop($d.r, $d.y)
    }
    # Snow falls slowly and sways.
    for ($i = 0; $i -lt $script:Flakes.Count; $i++) {
        $f = $script:Flakes[$i]
        if ($i -ge $s.snow) { $f.r.Visibility = 'Collapsed'; $f.y = -99; continue }
        if ($f.y -lt -50 -or $f.y -gt $h) {
            $f.x  = $script:Rnd.NextDouble() * $w
            $f.y  = $(if ($f.y -lt -50) { $script:Rnd.NextDouble() * $h } else { -2 })
            $f.v  = 0.3 + 0.35 * $script:Rnd.NextDouble()
            $f.ph = $script:Rnd.NextDouble() * 6.28
        }
        $f.y += $f.v
        $f.r.Visibility = 'Visible'
        [System.Windows.Controls.Canvas]::SetLeft($f.r, $f.x + 1.5 * [math]::Sin($s.tick / 9.0 + $f.ph) + $slant * $f.y / 4)
        [System.Windows.Controls.Canvas]::SetTop($f.r, $f.y)
    }

    # Thunderstorm: now and then the sky flashes, sometimes twice in a row.
    if ($kind.storm -and $s.flash -le 0 -and $script:Rnd.Next(140) -eq 0) { $s.flash = 7 }
    if ($s.flash -gt 0) {
        $Flash.Visibility = 'Visible'
        $Flash.Opacity = @(0, 0.18, 0.05, 0, 0.25, 0.1, 0.04)[$s.flash - 1]
        $s.flash--
    } else {
        $Flash.Visibility = 'Collapsed'
    }
}
