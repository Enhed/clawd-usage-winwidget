# ----------------------------------------------------------------- space ----
# The Space theme, after the one in clawd-usage-mac by @fl03er: a starfield behind
# the whole window - twinkling stars, drifting nebulae, a shooting star now and
# then - and in the sky row, in place of the weather, two slowly turning pixel
# planets (one ringed) and a little ship crossing. Stepped by the mascot's timer.

$script:Space = @{ on = $false; tick = 0; ship = 0.25; shoot = -1; sx = 0.0; sy = 0.0; broken = $false }

# The backdrop: a canvas between the theme's pattern layer and the window's content
# (Add-ThemeTo -Pattern has put a Grid [pattern, content] into the root Border).
$SpaceFx = New-Object System.Windows.Controls.Canvas
$SpaceFx.IsHitTestVisible = $false
$SpaceFx.Visibility = 'Collapsed'
$SpaceFx.Margin = $win.Content.Child.Children[0].Margin
$win.Content.Child.Children.Insert(1, $SpaceFx)
# Clipped to the window's rounded corners.
$SpaceFx.add_SizeChanged({
    $r = $win.Content.CornerRadius.TopLeft
    $SpaceFx.Clip = New-Object System.Windows.Media.RectangleGeometry (
        [System.Windows.Rect]::new(0, 0, $SpaceFx.ActualWidth, $SpaceFx.ActualHeight)), $r, $r
})

function New-SpaceShape($parent, [string]$kind, [double]$w, [double]$h, $fill) {
    $s = New-Object "System.Windows.Shapes.$kind"
    if ($w) { $s.Width = $w; $s.Height = $h }
    if ($fill) { $s.Fill = $(if ($fill -is [string]) { New-Brush $fill } else { $fill }) }
    [void]$parent.Children.Add($s)
    return $s
}

function New-Glow([string]$hex, [double]$a) {
    $c = ConvertTo-Color $hex
    return New-Object System.Windows.Media.RadialGradientBrush (
        [System.Windows.Media.Color]::FromArgb([byte](255 * $a), $c.R, $c.G, $c.B)),
        ([System.Windows.Media.Color]::FromArgb(0, $c.R, $c.G, $c.B))
}

# Nebulae: soft purple, pink and indigo clouds, drifting slowly.
$script:Nebulae = @()
foreach ($n in @(@('#7C3AED', 0.22), @('#DB2777', 0.13), @('#4F46E5', 0.15))) {
    $script:Nebulae += New-SpaceShape $SpaceFx Ellipse 10 10 (New-Glow $n[0] $n[1])
}

# Stars sit at fixed points over a strip taller than the window ever gets, so
# opening the details only uncovers more of them. The faint ones twinkle in groups,
# one path and one brush per group; the bright ones flare with a cross of light.
$SpaceStarColors = @('#FFFFFFFF', '#FFE9D5FF', '#FFC4B5FD', '#FFF9A8D4', '#FFA5B4FC', '#FF93C5FD')
$SpaceW = 262; $SpaceH = 900
$script:StarGroups = @()
for ($g = 0; $g -lt 10; $g++) {
    $p = New-SpaceShape $SpaceFx Path 0 0 $SpaceStarColors[$g % $SpaceStarColors.Count]
    $p.Data = New-Object System.Windows.Media.GeometryGroup
    $script:StarGroups += @{ p = $p; ph = $script:Rnd.NextDouble() * 6.28; v = 0.05 + 0.15 * $script:Rnd.NextDouble() }
}
for ($i = 0; $i -lt [int]($SpaceW * $SpaceH / 1100); $i++) {
    $sz = @(1, 1, 1, 1.5, 1.5, 2)[$script:Rnd.Next(6)]
    $script:StarGroups[$script:Rnd.Next(10)].p.Data.Children.Add([System.Windows.Media.RectangleGeometry]::new(
        [System.Windows.Rect]::new([math]::Round($script:Rnd.NextDouble() * $SpaceW),
                                   [math]::Round($script:Rnd.NextDouble() * $SpaceH), $sz, $sz)))
}
$script:BrightStars = @()
for ($i = 0; $i -lt 14; $i++) {
    $hex = $SpaceStarColors[$script:Rnd.Next($SpaceStarColors.Count)]
    $c = New-Object System.Windows.Controls.Canvas
    $c.Tag = [double]($script:Rnd.NextDouble() * $SpaceH)
    [System.Windows.Controls.Canvas]::SetLeft($c, [math]::Round($script:Rnd.NextDouble() * $SpaceW))
    [System.Windows.Controls.Canvas]::SetTop($c, [math]::Round($c.Tag))
    [void]$SpaceFx.Children.Add($c)
    $glow = New-SpaceShape $c Ellipse 14 14 (New-Glow $hex 0.25)
    [System.Windows.Controls.Canvas]::SetLeft($glow, -7); [System.Windows.Controls.Canvas]::SetTop($glow, -7)
    # Rays are 12 long around the centre, scaled to 4..12 as the star flares.
    $rays = @()
    foreach ($r in @([System.Windows.Rect]::new(-6, -0.5, 12, 1), [System.Windows.Rect]::new(-0.5, -6, 1, 12))) {
        $ray = New-SpaceShape $c Path 0 0 $hex
        $ray.Data = [System.Windows.Media.RectangleGeometry]::new($r)
        $ray.Opacity = 0.6
        $ray.RenderTransform = New-Object System.Windows.Media.ScaleTransform 1, 1
        $rays += $ray.RenderTransform
    }
    $core = New-SpaceShape $c Rectangle 2 2 $hex
    [System.Windows.Controls.Canvas]::SetLeft($core, -1); [System.Windows.Controls.Canvas]::SetTop($core, -1)
    $script:BrightStars += @{ c = $c; rays = $rays; ph = $script:Rnd.NextDouble() * 6.28; v = 0.05 + 0.15 * $script:Rnd.NextDouble() }
}

# A shooting star: a fading streak with a bright head, flying down and to the left.
$ShootFx = New-Object System.Windows.Controls.Canvas
$ShootFx.Visibility = 'Collapsed'
[void]$SpaceFx.Children.Add($ShootFx)
$tail = New-Object System.Windows.Shapes.Line
$tail.X1 = 0; $tail.Y1 = 0; $tail.X2 = 26; $tail.Y2 = -10; $tail.StrokeThickness = 1.2
$tail.Stroke = New-Object System.Windows.Media.LinearGradientBrush (
    (ConvertTo-Color '#CCFFFFFF'), (ConvertTo-Color '#00FFFFFF'), 0)
[void]$ShootFx.Children.Add($tail)
$head = New-SpaceShape $ShootFx Rectangle 2 2 '#FFFFFFFF'
[System.Windows.Controls.Canvas]::SetLeft($head, -1); [System.Windows.Controls.Canvas]::SetTop($head, -1)

# The sky row: its own canvas next to the weather's, which the theme hides.
$SpaceSky = New-Object System.Windows.Controls.Canvas
$SpaceSky.IsHitTestVisible = $false
$SpaceSky.Visibility = 'Collapsed'
$skyGrid = New-Object System.Windows.Controls.Grid
$UI.Sky.Child = $null
[void]$skyGrid.Children.Add($UI.SkyFx)
[void]$skyGrid.Children.Add($SpaceSky)
$UI.Sky.Child = $skyGrid

# Planets: a pixel sphere with bands of colour wrapped round it, lit from the upper
# left. A turn is $PlanetFrames bitmaps, each drawn the first time it is needed.
$PlanetFrames = 120
$PlanetDark = ConvertTo-Color '#FF0B0518'
$script:Planets = @(
    @{ fx = 0.52; fy = 0.45; amp = 0.07; r = 8; px = 1.6; spin = 0.5; seed = 1.3; ring = $false
       pal = @('#FF2E1065', '#FF6D28D9', '#FFA855F7', '#FFF472B6', '#FF67E8F9', '#FFC084FC') }
    @{ fx = 0.82; fy = 0.32; amp = 0.04; r = 5; px = 1.6; spin = 0.7; seed = 4.1; ring = $true
       pal = @('#FF1E1B4B', '#FF3730A3', '#FF6366F1', '#FFA5B4FC', '#FF818CF8') }
)

function New-PlanetFrame($p, [int]$k) {
    $n = 2 * $p.r + 1; $half = $n / 2.0
    $buf = New-Object byte[] ($n * $n * 4)
    $rot = 2 * [math]::PI * $k / $PlanetFrames
    for ($j = 0; $j -lt $n; $j++) {
        for ($i = 0; $i -lt $n; $i++) {
            $dx = ($i + 0.5 - $half) / $half; $dy = ($j + 0.5 - $half) / $half
            $rr = $dx * $dx + $dy * $dy
            if ($rr -gt 1) { continue }
            $z = [math]::Sqrt(1 - $rr)
            $u = [math]::Atan2($dx, $z) + $rot
            $noise = [math]::Sin($u * 3 + [math]::Sin($dy * 4 + $p.seed) * 1.6) +
                     0.6 * [math]::Sin($dy * 6 + $u * 2 + $p.seed) + 0.3 * [math]::Sin($u * 7 - $dy * 5)
            $idx = [math]::Min($p.cols.Count - 1, [math]::Max(0, [int][math]::Floor(($noise + 1.9) / 3.8 * $p.cols.Count)))
            $light = [math]::Max(0.12, [math]::Min(1, 0.3 + 0.9 * (-0.55 * $dx - 0.45 * $dy + 0.7 * $z)))
            $c = Mix-Color $PlanetDark $p.cols[$idx] $light
            $o = ($j * $n + $i) * 4
            $buf[$o] = $c.B; $buf[$o + 1] = $c.G; $buf[$o + 2] = $c.R; $buf[$o + 3] = 255
        }
    }
    $bmp = [System.Windows.Media.Imaging.BitmapSource]::Create($n, $n, 96, 96,
        [System.Windows.Media.PixelFormats]::Bgra32, $null, $buf, $n * 4)
    $bmp.Freeze()
    return $bmp
}

# A ring: the far half behind the planet, the near half in front.
function New-RingHalf($p, [double]$d, [bool]$back) {
    $e = New-SpaceShape $SpaceSky Ellipse ($d * 1.9) ($d * 0.44) $null
    $e.Stroke = New-Brush $p.pal[3]
    $e.StrokeThickness = 1.6
    $e.Opacity = $(if ($back) { 0.45 } else { 0.85 })
    $e.Clip = [System.Windows.Media.RectangleGeometry]::new(
        [System.Windows.Rect]::new(0, $(if ($back) { 0 } else { $d * 0.22 }), $d * 1.9, $d * 0.22))
    return $e
}

foreach ($p in $script:Planets) {
    $p.cols = @($p.pal | ForEach-Object { ConvertTo-Color $_ })
    $p.frames = @{}
    $p.d = (2 * $p.r + 1) * $p.px
    $p.glow = New-SpaceShape $SpaceSky Ellipse ($p.d * 2) ($p.d * 2) (New-Glow $p.pal[2] 0.28)
    if ($p.ring) { $p.back = New-RingHalf $p $p.d $true }
    $p.img = New-Object System.Windows.Controls.Image
    $p.img.Width = $p.d; $p.img.Height = $p.d
    [System.Windows.Media.RenderOptions]::SetBitmapScalingMode($p.img, 'NearestNeighbor')
    [void]$SpaceSky.Children.Add($p.img)
    if ($p.ring) { $p.front = New-RingHalf $p $p.d $false }
}

# The ship: a grey saucer with cyan windows and a flickering engine behind it.
$ShipPx = 1.6
$ShipArt = @('....##....', '..######..', '.##o##o##.', '##########', '.#..##..#.')
$ShipFx = New-Object System.Windows.Controls.Canvas
[void]$SpaceSky.Children.Add($ShipFx)
(New-SpaceShape $ShipFx Path 0 0 '#FF94A3B8').Data = New-PixelGeo $ShipArt $ShipPx
(New-SpaceShape $ShipFx Path 0 0 '#FF67E8F9').Data = New-PixelGeo $ShipArt $ShipPx 'o'
$ShipFlame = New-SpaceShape $ShipFx Rectangle 0 $ShipPx '#D9F472B6'
$ShipFlame.Height = $ShipPx
[System.Windows.Controls.Canvas]::SetTop($ShipFlame, 3 * $ShipPx)
$ShipSpark = New-SpaceShape $ShipFx Rectangle $ShipPx $ShipPx '#FFFDE68A'
[System.Windows.Controls.Canvas]::SetLeft($ShipSpark, -$ShipPx); [System.Windows.Controls.Canvas]::SetTop($ShipSpark, 3 * $ShipPx)

function Set-At($el, [double]$x, [double]$y) {
    [System.Windows.Controls.Canvas]::SetLeft($el, $x)
    [System.Windows.Controls.Canvas]::SetTop($el, $y)
}

function Step-Space {
    $s = $script:Space
    $s.tick++
    $t = $s.tick
    $w = $SpaceFx.ActualWidth; $h = $SpaceFx.ActualHeight
    if ($w -le 0 -or $h -le 0) { return }

    for ($i = 0; $i -lt $script:Nebulae.Count; $i++) {
        $e = $script:Nebulae[$i]
        $k = $t / 300.0 + $i * 2.1
        $rad = $w * (0.45 + 0.1 * $i)
        $e.Width = $rad * 2; $e.Height = $rad * 1.2
        Set-At $e ($w * (0.5 + 0.35 * [math]::Sin($k + $i)) - $rad) ($h * (0.3 + 0.25 * $i + 0.05 * [math]::Cos($k * 1.3)) - $rad * 0.6)
    }
    foreach ($g in $script:StarGroups) { $g.p.Opacity = 0.25 + 0.3 * (1 + [math]::Sin($t * $g.v + $g.ph)) }
    foreach ($b in $script:BrightStars) {
        if ($b.c.Tag -gt $h + 8) { continue }
        $tw = 0.5 + 0.5 * [math]::Sin($t * $b.v + $b.ph)
        $b.c.Opacity = 0.55 + 0.45 * $tw
        $len = (4 + 8 * $tw) / 12
        $b.rays[0].ScaleX = $len; $b.rays[1].ScaleY = $len
    }

    # A shooting star now and then: 14 ticks across, fading.
    if ($s.shoot -lt 0 -and $script:Rnd.Next(220) -eq 0) {
        $s.shoot = 0; $s.sx = $w * (0.3 + 0.7 * $script:Rnd.NextDouble()); $s.sy = $h * 0.35 * $script:Rnd.NextDouble()
    }
    if ($s.shoot -ge 0) {
        $k = $s.shoot / 14.0
        $ShootFx.Visibility = 'Visible'
        $ShootFx.Opacity = 1 - $k
        Set-At $ShootFx ($s.sx - $k * 120) ($s.sy + $k * 45)
        $s.shoot = $(if ($s.shoot -ge 14) { -1 } else { $s.shoot + 1 })
    } else { $ShootFx.Visibility = 'Collapsed' }

    # The sky row: the planets sway to and fro, turning and bobbing; the ship crosses.
    $sw = $UI.Sky.ActualWidth; $sh = $UI.Sky.ActualHeight
    if ($UI.Sky.Visibility -ne 'Visible' -or $sw -le 0) { return }
    foreach ($p in $script:Planets) {
        $f = [int][math]::Floor($t * $p.spin) % $PlanetFrames
        if (-not $p.frames.ContainsKey($f)) { $p.frames[$f] = New-PlanetFrame $p $f }
        $p.img.Source = $p.frames[$f]
        $cx = $sw * ($p.fx + $p.amp * [math]::Sin($t / 250.0 + $p.seed))
        $cy = $sh * $p.fy + 2 * [math]::Sin($t / 45.0 + $p.seed)
        $x = [math]::Round($cx - $p.d / 2); $y = [math]::Round($cy - $p.d / 2)
        Set-At $p.img $x $y
        Set-At $p.glow ($cx - $p.d) ($cy - $p.d)
        if ($p.ring) {
            Set-At $p.back ($cx - $p.d * 0.95) ($cy - $p.d * 0.22)
            Set-At $p.front ($cx - $p.d * 0.95) ($cy - $p.d * 0.22)
        }
    }
    $s.ship += 0.002
    if ($s.ship -gt 1.4) { $s.ship = 0.25 }
    Set-At $ShipFx ([math]::Round($s.ship * $sw)) ([math]::Round(3 + 2 * [math]::Sin($t / 12.0)))
    $fl = (2 + $t % 4) * $ShipPx
    $ShipFlame.Width = $fl
    [System.Windows.Controls.Canvas]::SetLeft($ShipFlame, -$fl)
}

# On with the Space theme: the backdrop shows, and the sky row trades the weather
# for the planets (the sky's own colour would hide the stars behind it).
function Sync-Space {
    $on = ((Get-ThemeId) -eq 'space') -and -not $script:Space.broken
    $script:Space.on = $on
    $vis = $(if ($on) { 'Visible' } else { 'Collapsed' })
    $SpaceFx.Visibility = $vis
    $SpaceSky.Visibility = $vis
    $UI.SkyFx.Visibility = $(if ($on) { 'Collapsed' } else { 'Visible' })
    $UI.Sky.Background = $(if ($on) { $null } else { $SkyBrush })
    if ($on) { Step-Space }
}
Sync-Space
