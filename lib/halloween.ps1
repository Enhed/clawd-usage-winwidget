# ------------------------------------------------------------- halloween ----
# The Halloween theme, a spooky night: behind the whole window fog creeping along
# the bottom, will-o'-the-wisps drifting, bats flapping across, a ghost floating
# by now and then and a spider letting itself down from its web in the corner; in
# the sky row a big moon over a graveyard - tombstones, a cross, a dead tree and
# jack-o'-lanterns grinning with a flickering light. Clawd's Witch hat suits it.

$SpookFx  = New-SceneBackdrop
$SpookSky = New-SceneSky
$SpookPx  = 1.6
$script:Spook = @{ w = 0; ghost = $null; wait = 80; spider = 0.0; spiderT = 0; scare = -1; night = $null }

# Fog: soft green and purple clouds creeping along the bottom.
$script:SpookFog = @()
foreach ($f in @(@('#86EFAC', 0.10), @('#A78BFA', 0.12), @('#86EFAC', 0.08), @('#C4B5FD', 0.10))) {
    $script:SpookFog += @{ e = (New-SceneShape $SpookFx Ellipse 10 10 (New-Glow $f[0] $f[1])); ph = $script:Rnd.NextDouble() * 6.28 }
}

# Will-o'-the-wisps: little green lights wandering, glowing up and dying down.
$script:Wisps = @()
for ($i = 0; $i -lt 6; $i++) {
    $c = New-Object System.Windows.Controls.Canvas
    [void]$SpookFx.Children.Add($c)
    $g = New-SceneShape $c Ellipse 12 12 (New-Glow '#4ADE80' 0.5)
    Set-At $g -6 -6
    $d = New-SceneShape $c Rectangle 2 2 '#FFBBF7D0'
    Set-At $d -1 -1
    $script:Wisps += @{ c = $c; fx = $script:Rnd.NextDouble(); fy = 0.2 + 0.75 * $script:Rnd.NextDouble()
                        ph = $script:Rnd.NextDouble() * 6.28; v = 0.02 + 0.03 * $script:Rnd.NextDouble() }
}

# A web in the top right corner, and its spider going down and up on a thread.
$SpookWeb = New-ScenePixels $SpookFx @(
    'w..w...w..w',
    '.w.w..w..w.',
    '..wwwwwww..',
    'ww.w.w..w..',
    '..w..ww.w..',
    '.w..w..ww..',
    'w..w...w.w.',
    '..w...w..w.',
    '.w...w....w',
    'w...w......'
) 2 @{ w = '#59E9D5FF' }
$SpookThread = New-SceneShape $SpookFx Rectangle 1 0 '#59E9D5FF'
$SpookSpider = New-ScenePixels $SpookFx @('w..kk..w', '.wkkkkw.', 'wkrkkrkw', '.wkkkkw.', 'w.w..w.w') 1.5 @{
    k = '#FF1C1326'; w = '#FF9F86C0'; r = '#FFF87171' }

# Bats: two frames of wings, flying across in loops.
function New-BatFrames($parent) {
    $c = New-Object System.Windows.Controls.Canvas
    [void]$parent.Children.Add($c)
    $colors = @{ b = '#FF7353A0'; r = '#FFF87171' }
    $up   = New-ScenePixels $c @('b.........b', 'bb..b.b..bb', '.bbbrbrbbb.', '....bbb....') $SpookPx $colors
    $down = New-ScenePixels $c @('....b.b....', '..bbrbrbb..', '.bbbbbbbbb.', 'bb.......bb') $SpookPx $colors
    return @{ c = $c; up = $up; down = $down; x = $null; y = 0.0; v = 0.0; ph = 0.0; amp = 0.0; first = $true }
}
$script:Bats = @()
for ($i = 0; $i -lt 3; $i++) { $script:Bats += New-BatFrames $SpookFx }

# The ghost: floats across the window, bobbing, its hem waving in two frames.
$SpookGhost = New-Object System.Windows.Controls.Canvas
$SpookGhost.Visibility = 'Collapsed'
[void]$SpookFx.Children.Add($SpookGhost)
$GhostBody = @('...wwwww...', '.wwwwwwwww.', 'wwwwwwwwwww', 'wwkkwwwkkww', 'wwkkwwwkkww', 'wwwwwwwwwww',
               'wwwwwkwwwww', 'wwwwkkkwwww', 'wwwwwkwwwww', 'wwwwwwwwwww', 'wwwwwwwwwww')
$GhostColors = @{ w = '#FFF5F3FF'; k = '#FF1C1326' }
$GhostHem = @(
    (New-ScenePixels $SpookGhost ($GhostBody + @('ww.www.www.', 'w...w...w..')) 2 $GhostColors),
    (New-ScenePixels $SpookGhost ($GhostBody + @('.www.www.ww', '..w...w...w')) 2 $GhostColors)
)

# The sky row: the moon with its glow and craters, behind everything else.
$SpookMoon = New-Object System.Windows.Controls.Canvas
[void]$SpookSky.Children.Add($SpookMoon)
$MoonGlow = New-SceneShape $SpookMoon Ellipse 44 44 (New-Glow '#FDBA74' 0.45)
Set-At $MoonGlow (5.5 * $SpookPx - 22) (5.5 * $SpookPx - 22)
[void](New-ScenePixels $SpookMoon @(
    '...mmmmm...',
    '..mmmmmmm..',
    '.mmmmmmcmm.',
    'mmccmmmmmmm',
    'mmccmmmmmmm',
    'mmmmmmmmccm',
    'mmmmmmmmccm',
    '.mmmcmmmmm.',
    '..mmmmmmm..',
    '...mmmmm...'
) $SpookPx @{ m = '#FFFDE68A'; c = '#FFF5C66B' })

# The graveyard: a dead tree, tombstones and a cross, the ground in front of them.
$SpookTree = New-ScenePixels $SpookSky @(
    '.t.....t....',
    '..t...t..t..',
    't..t.t..t...',
    '.t..tt.t....',
    '..t.tttt....',
    '...ttt......',
    '....tt......',
    '....tt......',
    '....tt......',
    '...tttt.....'
) $SpookPx @{ t = '#FF5B4A66' }
$TombArt = @('..sss..', '.sssss.', 'sssdsss', 'ssdddss', 'sssdsss', 'sssdsss', 'sssssss', 'sssssss')
$TombColors = @{ s = '#FF6B6478'; d = '#FF453E52' }
$script:Tombs = @(
    @{ c = (New-ScenePixels $SpookSky $TombArt $SpookPx $TombColors); fx = 0.31; h = 8 }
    @{ c = (New-ScenePixels $SpookSky @('..c..', 'ccccc', '..c..', '..c..', '..c..', '..c..') $SpookPx @{ c = '#FF6B6478' }); fx = 0.38; h = 6 }
    @{ c = (New-ScenePixels $SpookSky @('.sssss.', 'sssssss', 'sdsdsds', 'sssssss', 'sssssss') $SpookPx $TombColors); fx = 0.66; h = 5 }
)

# Jack-o'-lanterns: the face is a layer of its own, flickering like a candle inside.
$PumpkinArt = @('....g....', '.ooogooo.', 'oyyoooyyo', 'ooyoooyoo', 'ooooooooo', 'oyoyyyoyo', '.oyyyyyo.')
$script:Pumpkins = @()
foreach ($fx in @(0.24, 0.58)) {
    $c = New-Object System.Windows.Controls.Canvas
    [void]$SpookSky.Children.Add($c)
    $glow = New-SceneShape $c Ellipse 26 26 (New-Glow '#FB923C' 0.5)
    Set-At $glow (4.5 * $SpookPx - 13) (3.5 * $SpookPx - 13)
    [void](New-ScenePixels $c $PumpkinArt $SpookPx @{ o = '#FFEA580C'; g = '#FF4D7C0F' })
    $face = New-ScenePixels $c $PumpkinArt $SpookPx @{ y = '#FFFDE047' }
    $dark = New-ScenePixels $c $PumpkinArt $SpookPx @{ y = '#FF7C2D12' }
    $c.Children.Remove($dark); $c.Children.Insert(2, $dark)
    $script:Pumpkins += @{ c = $c; glow = $glow; face = $face; fx = $fx; ph = $script:Rnd.NextDouble() * 6.28 }
}

$groundArt = @('', '', '')
for ($x = 0; $x -lt 170; $x++) {
    $groundArt[0] += $(if ($script:Rnd.Next(5) -eq 0) { 'g' } else { '.' })
    $groundArt[1] += $(if ($script:Rnd.Next(3) -eq 0) { 'g' } else { 'd' })
    $groundArt[2] += 'd'
}
$SpookGround = New-ScenePixels $SpookSky $groundArt $SpookPx @{ d = '#FF2E1F3D'; g = '#FF3F2F52' }

# The scare, a secret: at midnight, and not every night, lightning flashes
# twice, the lights go out and a huge face with burning eyes and a jagged grin looms
# out of the dark behind the window, blinks and fades - and Clawd jumps.
$ScareLen = 70
$SpookDark = New-SceneShape $SpookFx Rectangle 10 10 '#FF07040B'
$SpookFlash = New-SceneShape $SpookFx Rectangle 10 10 '#FFF5F3FF'
$SpookFace = New-Object System.Windows.Controls.Canvas
[void]$SpookFx.Children.Add($SpookFace)
$FacePx = 6
$FaceArt = @(
    'rrr................rrr',
    'rrrrr............rrrrr',
    'rryyrr..........rryyrr',
    'rryyrr..........rryyrr',
    'rryyrr..........rryyrr',
    '.rrrr............rrrr.',
    '......................',
    '......................',
    'm....................m',
    'mm..................mm',
    '.mmwmmwmmwmmwmmwmmwmm.',
    '..mmmmmmmmmmmmmmmmmm..',
    '....mmwmmwmmwmmwmm....',
    '.......mmmmmmmm.......'
)
foreach ($x in @(3, 19)) {
    $g = New-SceneShape $SpookFace Ellipse 70 70 (New-Glow '#DC2626' 0.6)
    Set-At $g ($x * $FacePx - 35) (3 * $FacePx - 35)
}
$FaceMouth = New-ScenePixels $SpookFace $FaceArt $FacePx @{ m = '#FFEA580C'; w = '#FF07040B' }
$FaceEyes = New-ScenePixels $SpookFace $FaceArt $FacePx @{ r = '#FFDC2626'; y = '#FFFEF08A' }
$FaceW = 22 * $FacePx; $FaceH = 14 * $FacePx
foreach ($e in @($SpookDark, $SpookFlash, $SpookFace)) { $e.Opacity = 0; $e.Visibility = 'Collapsed' }

function Step-Scare([int]$k, [double]$w, [double]$h) {
    $vis = $(if ($k -ge 0) { 'Visible' } else { 'Collapsed' })
    foreach ($e in @($SpookDark, $SpookFlash, $SpookFace)) { $e.Visibility = $vis }
    if ($k -lt 0) { $SpookSky.Opacity = 1; return }
    $SpookDark.Width = $w; $SpookDark.Height = $h
    $SpookFlash.Width = $w; $SpookFlash.Height = $h
    # Two flashes of lightning, the dark falls, the face looms, holds, blinks, fades.
    $SpookFlash.Opacity = $(switch ($k) { 0 { 0.5 } 1 { 0.15 } 3 { 0.4 } 4 { 0.1 } default { 0 } })
    $dark = $(if ($k -lt 4) { 0 } elseif ($k -lt 12) { ($k - 4) / 8.0 } elseif ($k -lt $ScareLen - 12) { 1 }
              else { ($ScareLen - $k) / 12.0 })
    $SpookDark.Opacity = 0.8 * $dark
    $SpookSky.Opacity = 1 - 0.6 * $dark
    $SpookFace.Opacity = $(if ($k -lt 12) { 0 } elseif ($k -lt 30) { ($k - 12) / 18.0 } elseif ($k -lt $ScareLen - 16) { 1 }
                           else { [math]::Max(0, ($ScareLen - 6 - $k) / 10.0) })
    $FaceEyes.Visibility = $(if ($k -ge 40 -and $k -lt 43) { 'Collapsed' } else { 'Visible' })
    # Creeping a little closer while it is there.
    $z = 0.9 + 0.15 * $k / $ScareLen
    $SpookFace.RenderTransform = New-Object System.Windows.Media.ScaleTransform $z, $z, ($FaceW / 2), ($FaceH / 2)
    Set-At $SpookFace ([math]::Round(($w - $FaceW) / 2)) ([math]::Round(($h - $FaceH) * 0.4))
    # Clawd startles - unless he is asleep, lying flat or busy with something already.
    if ($k -eq 24) {
        $m = $script:Mz
        if ($m -and -not $m.act -and $m.mood -ne 'dead' -and $m.cur -ne 'dead' -and -not $m.buried) { Start-MascotAct 'jump' }
    }
}

function Step-Halloween([int]$t) {
    $s = $script:Spook
    $w = $SpookFx.ActualWidth; $h = $SpookFx.ActualHeight
    if ($w -le 0 -or $h -le 0) { return }

    for ($i = 0; $i -lt $script:SpookFog.Count; $i++) {
        $f = $script:SpookFog[$i]
        $fw = $w * (0.7 + 0.15 * $i); $fh = 70 + 15 * $i
        $f.e.Width = $fw; $f.e.Height = $fh
        $f.e.Opacity = 0.7 + 0.3 * [math]::Sin($t / 40.0 + $f.ph)
        Set-At $f.e ($w * (0.5 + 0.45 * [math]::Sin($t / (260.0 + 40 * $i) + $f.ph)) - $fw / 2) ($h - $fh * 0.55)
    }
    foreach ($o in $script:Wisps) {
        $o.c.Opacity = [math]::Max(0, [math]::Sin($t * $o.v + $o.ph))
        if ($o.c.Opacity -le 0.01) { $o.fx = $script:Rnd.NextDouble(); $o.fy = 0.2 + 0.75 * $script:Rnd.NextDouble() }
        Set-At $o.c ($o.fx * $w + 6 * [math]::Sin($t / 23.0 + $o.ph)) ($o.fy * $h + 4 * [math]::Cos($t / 31.0 + $o.ph))
    }

    # The spider: rests up in the web, then lets itself down and climbs back.
    # Flush with the right edge, the thread clear of the window's buttons.
    $wx = $w - 22
    Set-At $SpookWeb $wx 0
    $s.spiderT++
    $cycle = $s.spiderT % 400
    $s.spider = $(if ($cycle -lt 150) { 0 } elseif ($cycle -lt 230) { ($cycle - 150) / 80.0 } elseif ($cycle -lt 300) { 1 }
                  else { 1 - ($cycle - 300) / 100.0 })
    $sy = 10 + 50 * $s.spider + $(if ($cycle -ge 230 -and $cycle -lt 300) { 2 * [math]::Sin($t / 6.0) } else { 0 })
    $SpookThread.Height = $sy
    Set-At $SpookThread ($w - 8) 0
    Set-At $SpookSpider ($w - 14) $sy

    foreach ($b in $script:Bats) {
        if ($null -eq $b.x) {
            # The first time anywhere in the window, later from off the left edge.
            $b.x = $(if ($b.first) { $w * $script:Rnd.NextDouble() } else { -20 - $w * 2 * $script:Rnd.NextDouble() })
            $b.first = $false
            $b.y = $h * (0.05 + 0.5 * $script:Rnd.NextDouble())
            $b.v = 0.9 + 0.8 * $script:Rnd.NextDouble(); $b.amp = 4 + 10 * $script:Rnd.NextDouble()
            $b.ph = $script:Rnd.NextDouble() * 6.28
        }
        $b.x += $b.v
        if ($b.x -gt $w + 20) { $b.x = $null; continue }
        $flap = ([int][math]::Floor($t / 2 + $b.ph) % 2) -eq 0
        $b.up.Visibility = $(if ($flap) { 'Visible' } else { 'Collapsed' })
        $b.down.Visibility = $(if ($flap) { 'Collapsed' } else { 'Visible' })
        Set-At $b.c ([math]::Round($b.x)) ([math]::Round($b.y + $b.amp * [math]::Sin($t / 9.0 + $b.ph)))
    }

    # The ghost: after a while away, across the window from the right, fading in and out.
    if ($null -eq $s.ghost) {
        $s.wait--
        if ($s.wait -le 0) { $s.ghost = 0.0; $s.gy = $h * (0.25 + 0.4 * $script:Rnd.NextDouble()); $SpookGhost.Visibility = 'Visible' }
    } else {
        $s.ghost += 0.004
        if ($s.ghost -ge 1) {
            $s.ghost = $null; $s.wait = 300 + $script:Rnd.Next(500)
            $SpookGhost.Visibility = 'Collapsed'
        } else {
            $SpookGhost.Opacity = 0.45 * [math]::Sin([math]::PI * $s.ghost)
            $hem = [int]([math]::Floor($t / 5) % 2)
            $GhostHem[0].Visibility = $(if ($hem -eq 0) { 'Visible' } else { 'Collapsed' })
            $GhostHem[1].Visibility = $(if ($hem -eq 1) { 'Visible' } else { 'Collapsed' })
            Set-At $SpookGhost ([math]::Round($w - ($w + 22) * $s.ghost)) ([math]::Round($s.gy + 6 * [math]::Sin($t / 12.0)))
        }
    }

    # Midnight strikes - one night in three, while the window is on screen.
    if ($s.scare -lt 0 -and $t % 10 -eq 0) {
        $now = Get-Date
        if ($now.Hour -eq 0 -and $now.Minute -eq 0 -and $s.night -ne $now.Date) {
            $s.night = $now.Date
            if ($script:Rnd.Next(3) -eq 0) { $s.scare = 0 }
        }
    }
    if ($s.scare -ge 0) {
        Step-Scare $s.scare $w $h
        $s.scare++
        if ($s.scare -ge $ScareLen) { $s.scare = -1; Step-Scare -1 $w $h }
    }

    # The sky row.
    $sw = $UI.Sky.ActualWidth; $sh = $UI.Sky.ActualHeight
    if ($UI.Sky.Visibility -ne 'Visible' -or $sw -le 0) { return }
    $floor = $sh - 3 * $SpookPx
    Set-At $SpookGround 0 $floor
    Set-At $SpookMoon ([math]::Round($sw * 0.46)) 3
    $MoonGlow.Opacity = 0.8 + 0.2 * [math]::Sin($t / 30.0)
    Set-At $SpookTree ([math]::Round($sw * 0.13)) ($floor + $SpookPx - 10 * $SpookPx)
    foreach ($g in $script:Tombs) { Set-At $g.c ([math]::Round($sw * $g.fx)) ($floor + $SpookPx - $g.h * $SpookPx) }
    foreach ($p in $script:Pumpkins) {
        $fl = 0.65 + 0.2 * [math]::Sin($t / 2.3 + $p.ph) + 0.15 * [math]::Sin($t / 1.3 + $p.ph * 2)
        $p.face.Opacity = $fl; $p.glow.Opacity = $fl
        Set-At $p.c ([math]::Round($sw * $p.fx)) ($floor + $SpookPx - 7 * $SpookPx)
    }
}

$Scenes.halloween = @{ back = $SpookFx; sky = $SpookSky; step = ${function:Step-Halloween} }
Sync-Scene
