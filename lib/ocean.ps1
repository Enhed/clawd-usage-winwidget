# ----------------------------------------------------------------- ocean ----
# The Underwater theme, a cartoon sea: sunbeams swaying down from the surface and
# bubbles rising behind the whole window; in the sky row pastel flowers drifting in
# the water like clouds, a strip of sand with a starfish and swaying kelp, fish
# swimming across and a jellyfish pulsing. Clawd's astronaut helmet suits it.

$OceanFx  = New-SceneBackdrop
$OceanSky = New-SceneSky
$script:Ocean = @{ w = 0 }

# Light from the surface: a glow along the top and a few slanting beams.
$OceanSurf = New-SceneShape $OceanFx Rectangle 10 70 (New-Fade '#67E8F9' 0.16)
$script:Beams = @()
foreach ($beam in @(@(0.12, 18), @(0.38, 26), @(0.6, 14), @(0.84, 22))) {
    $r = New-SceneShape $OceanFx Rectangle $beam[1] 320 (New-Fade '#E0F2FE' 0.05)
    $r.RenderTransform = New-Object System.Windows.Media.SkewTransform -20, 0
    $script:Beams += @{ r = $r; fx = $beam[0]; ph = $script:Rnd.NextDouble() * 6.28 }
}

# Flowers: five round petals and a heart, in the pixel grid, drifting slowly - the
# sea's clouds. Created first, so that they stay behind the rest of the sky row.
function New-FlowerArt([int]$n) {
    $rows = @(); $half = $n / 2.0
    for ($j = 0; $j -lt $n; $j++) {
        $row = ''
        for ($i = 0; $i -lt $n; $i++) {
            $dx = ($i + 0.5 - $half) / $half; $dy = ($j + 0.5 - $half) / $half
            $r = [math]::Sqrt($dx * $dx + $dy * $dy)
            $edge = 0.55 + 0.45 * [math]::Abs([math]::Cos(2.5 * [math]::Atan2($dy, $dx)))
            $row += $(if ($r -lt 0.3) { 'c' } elseif ($r -le $edge) { 'p' } else { '.' })
        }
        $rows += $row
    }
    return $rows
}
$script:Flowers = @()
$i = 0
foreach ($pc in @(@('#FF7DD3FC', '#FFFEF9C3'), @('#FFF9A8D4', '#FFFEF9C3'), @('#FF86EFAC', '#FFFEF9C3'),
                  @('#FFC4B5FD', '#FFFEF9C3'))) {
    $n = @(9, 11, 13)[$i % 3]
    $c = New-ScenePixels $OceanSky (New-FlowerArt $n) 1.6 @{ p = $pc[0]; c = $pc[1] }
    $c.Opacity = 0.6
    $script:Flowers += @{ c = $c; size = $n * 1.6; x = $null; fy = 0.02 + 0.12 * $script:Rnd.NextDouble()
                          v = 0.06 + 0.08 * $script:Rnd.NextDouble(); ph = $script:Rnd.NextDouble() * 6.28 }
    $i++
}

# Bubbles rise from below, wobbling.
$script:Bubbles = @()
for ($i = 0; $i -lt 14; $i++) {
    $d = 3 + $script:Rnd.Next(5)
    $e = New-SceneShape $OceanFx Ellipse $d $d $null
    $e.Stroke = New-SceneBrush '#99E0F2FE'
    $e.StrokeThickness = 1
    $script:Bubbles += @{ e = $e; x = 0.0; y = -99.0; v = 0.0; ph = 0.0 }
}

# The sky row's floor: sand with a starfish; kelp grows from it.
$OceanPx = 1.6
$sand = @('', '', '')
for ($x = 0; $x -lt 170; $x++) {
    $sand[0] += $(if ($script:Rnd.Next(10) -lt 3) { 's' } else { '.' })
    $sand[1] += $(if ($script:Rnd.Next(12) -eq 0) { 'd' } else { 's' })
    $sand[2] += 's'
}
$OceanSand = New-ScenePixels $OceanSky $sand $OceanPx @{ s = '#CCE2C98F'; d = '#CCB8975F' }
$OceanStar = New-ScenePixels $OceanSky @('..o..', 'ooooo', '.ooo.', '.o.o.') $OceanPx @{ o = '#FFFB923C' }

$script:Kelp = @()
foreach ($k in @(@(0.31, 14), @(0.36, 10), @(0.62, 12), @(0.74, 16))) {
    $rows = @()
    for ($r = 0; $r -lt $k[1]; $r++) {
        $pos = [int][math]::Round(1.5 + 1.2 * [math]::Sin($r * 0.8 + $k[0] * 20))
        $leaf = $(if ($r % 4 -eq 1) { 'l' } else { '.' })
        $rows += ('.' * $pos) + 'kk' + $leaf + ('.' * (3 - $pos))
    }
    $c = New-ScenePixels $OceanSky $rows $OceanPx @{ k = '#FF15803D'; l = '#FF4ADE80' }
    $c.Opacity = 0.85
    $h = $k[1] * $OceanPx
    $c.RenderTransform = New-Object System.Windows.Media.SkewTransform 0, 0, (3 * $OceanPx), $h
    $script:Kelp += @{ c = $c; fx = $k[0]; h = $h; ph = $script:Rnd.NextDouble() * 6.28 }
}

# Fish: a striped yellow one swimming left, a small pink one swimming right.
$script:Fish = @(
    @{ c = (New-ScenePixels $OceanSky @('...yyyy....', '.yyybyyb.yy', 'yeyybyybyyy', '.yyybyyb.yy', '...yyyy....') $OceanPx `
                @{ y = '#FFFACC15'; b = '#FF38BDF8'; e = '#FF0F172A' })
       w = 11 * $OceanPx; dir = -1; v = 0.55; x = $null; fy = 0.3; ph = 0.0 }
    @{ c = (New-ScenePixels $OceanSky @('.p.ppp..', 'ppppppep', '.p.pppp.') $OceanPx @{ p = '#FFFB7185'; e = '#FF0F172A' })
       w = 8 * $OceanPx; dir = 1; v = 0.8; x = $null; fy = 0.5; ph = 0.0 }
)

# A jellyfish: its bell pulses, its tentacles wave in two frames.
$OceanJelly = New-Object System.Windows.Controls.Canvas
[void]$OceanSky.Children.Add($OceanJelly)
$JellyBell = New-ScenePixels $OceanJelly @('...jjj...', '.jjjjjjj.', 'jjhjjjjjj', 'jjjjjjjjj') $OceanPx @{ j = '#D9F0ABFC'; h = '#FFFFFFFF' }
$JellyBell.RenderTransform = New-Object System.Windows.Media.ScaleTransform 1, 1, (4.5 * $OceanPx), (4 * $OceanPx)
$JellyLegs = @(
    (New-ScenePixels $OceanJelly @('', '', '', '', '.j.j.j.j.', 'j.j.j.j..') $OceanPx @{ j = '#B3F0ABFC' }),
    (New-ScenePixels $OceanJelly @('', '', '', '', '.j.j.j.j.', '..j.j.j.j') $OceanPx @{ j = '#B3F0ABFC' })
)

function Step-Ocean([int]$t) {
    $w = $OceanFx.ActualWidth; $h = $OceanFx.ActualHeight
    if ($w -le 0 -or $h -le 0) { return }
    if ($w -ne $script:Ocean.w) { $script:Ocean.w = $w; $OceanSurf.Width = $w }

    foreach ($b in $script:Beams) {
        $b.r.Opacity = 0.6 + 0.4 * [math]::Sin($t / 25.0 + $b.ph)
        $b.r.RenderTransform.AngleX = -20 + 4 * [math]::Sin($t / 60.0 + $b.ph)
        Set-At $b.r ($b.fx * $w) 0
    }
    foreach ($b in $script:Bubbles) {
        if ($b.y -lt -10) {
            $b.x = $script:Rnd.NextDouble() * $w
            $b.y = $(if ($b.y -lt -50) { $script:Rnd.NextDouble() * $h } else { $h + 5 })
            $b.v = 0.35 + 0.6 * $script:Rnd.NextDouble(); $b.ph = $script:Rnd.NextDouble() * 6.28
        }
        $b.y -= $b.v
        Set-At $b.e ($b.x + 2 * [math]::Sin($t / 8.0 + $b.ph)) $b.y
    }

    # The sky row: sand underfoot, kelp swaying, fish and the jellyfish.
    $sw = $UI.Sky.ActualWidth; $sh = $UI.Sky.ActualHeight
    if ($UI.Sky.Visibility -ne 'Visible' -or $sw -le 0) { return }
    foreach ($f in $script:Flowers) {
        if ($null -eq $f.x) { $f.x = $script:Rnd.NextDouble() * $sw }
        $f.x += $f.v
        if ($f.x -gt $sw) { $f.x = -$f.size }
        Set-At $f.c ([math]::Round($f.x)) ([math]::Round($f.fy * $sh + 3 * [math]::Sin($t / 40.0 + $f.ph)))
    }
    $floor = $sh - 3 * $OceanPx
    Set-At $OceanSand 0 $floor
    Set-At $OceanStar ([math]::Round($sw * 0.52)) ($floor - 3 * $OceanPx)
    foreach ($k in $script:Kelp) {
        $k.c.RenderTransform.AngleX = 9 * [math]::Sin($t / 14.0 + $k.ph)
        Set-At $k.c ([math]::Round($sw * $k.fx)) ($floor + $OceanPx - $k.h)
    }
    foreach ($f in $script:Fish) {
        if ($null -eq $f.x) {
            # Off screen for a while, then in again from its side at another depth.
            $f.x = $(if ($f.dir -lt 0) { $sw + $sw * $script:Rnd.NextDouble() } else { -$f.w - $sw * $script:Rnd.NextDouble() })
            $f.fy = 0.15 + 0.4 * $script:Rnd.NextDouble(); $f.ph = $script:Rnd.NextDouble() * 6.28
        }
        $f.x += $f.dir * $f.v
        if (($f.dir -lt 0 -and $f.x -lt -$f.w) -or ($f.dir -gt 0 -and $f.x -gt $sw)) { $f.x = $null; continue }
        Set-At $f.c ([math]::Round($f.x)) ([math]::Round($f.fy * $sh + 1.5 * [math]::Sin($t / 10.0 + $f.ph)))
    }
    $pulse = [math]::Max(0, [math]::Sin($t / 4.0))
    $JellyBell.RenderTransform.ScaleY = 1 - 0.15 * $pulse
    $JellyBell.RenderTransform.ScaleX = 1 + 0.08 * $pulse
    $leg = [int]([math]::Floor($t / 4) % 2)
    $JellyLegs[0].Visibility = $(if ($leg -eq 0) { 'Visible' } else { 'Collapsed' })
    $JellyLegs[1].Visibility = $(if ($leg -eq 1) { 'Visible' } else { 'Collapsed' })
    Set-At $OceanJelly ([math]::Round($sw * (0.5 + 0.1 * [math]::Sin($t / 220.0)))) ([math]::Round($sh * 0.12 + 3 * [math]::Sin($t / 18.0)))
}

$Scenes.ocean = @{ back = $OceanFx; sky = $OceanSky; step = ${function:Step-Ocean} }
Sync-Scene
