# ---------------------------------------------------------------- mascot ----
# Clawd from the Claude Code welcome screen - built from the same block glyphs as in
# the terminal (Claude Code 2.1.301), with the same click animations. State comes
# from the session registry and limits: nothing running - burrows into the sand
# and sleeps with only the eyes sticking out, like a crab in a burrow; sessions
# idle - wanders, and after 10 quiet minutes dozes standing; something working -
# runs; a session awaits input - hops with "?"; session limit used up - lies
# legs up. One-shot animations play on top. Right-click the mascot - developer mode.

# Clawd is 9 cells by 3 rows. Each cell is split into 2x4 pixels: that way
# quadrant glyphs and the "lower quarter" (eyelid) fit the grid losslessly,
# and a pixel comes out almost square, as in the terminal.
$ClawdCols  = 9
$ClawdRows  = 3
$MascotPx   = 2.0
$MascotPy   = 2.2
$MascotW    = 2 * $ClawdCols * $MascotPx
# The lower half of the legs row is empty - the canvas is lowered by it to the "ground".
$MascotSink = 2 * $MascotPy
$script:MascotGeo = @{}

# Glyph quadrants as bits: 1 - top-left, 2 - top-right, 4 - bottom-left, 8 - bottom-right.
$ClawdQuad = @{}
foreach ($p in @(' 0', '█15', '▀3', '▄12', '▌5', '▐10', '▘1', '▝2', '▖4', '▗8',
                 '▛7', '▜11', '▙13', '▟14')) {
    $ClawdQuad[$p[0]] = [int]$p.Substring(1)
}

# Arms: what sits left and right of the eyes (row 0) and of the chest (row 1).
$ClawdArms = @{
    down  = @{ r1L = ' ▐'; r1R = '';  r2L = '▝▜'; r2R = '█▀' }
    up    = @{ r1L = '▗▟'; r1R = '▄'; r2L = ' ▜'; r2R = '█▘' }
    right = @{ r1L = ' ▐'; r1R = '▄'; r2L = '▝▜'; r2R = '█▘' }   # one-up in Claude Code
    left  = @{ r1L = '▗▟'; r1R = '';  r2L = ' ▜'; r2R = '█▀' }
}
$ClawdFeet = @{
    both  = ' ▝▝   ▝▝ '
    left  = ' ▝▝      '
    right = '      ▝▝ '
}
# Turns in place: glyph rows and columns from..to where the black face shows.
$ClawdFacing = @{
    'right-12' = @(@(' ▐█▜██▛█ ', 2, 8), @('▝▜██████▀', 2, 7), @(' ▝▝   ▝▝ ', 0, 0))
    'right-30' = @(@('  █▛██▛▌ ', 2, 7), @(' ▝█████▛ ', 2, 7), @('  ▘▘  ▘▘ ', 0, 0))
    'right-55' = @(@('  ▐█▛█▜  ', 3, 7), @('  ▐████  ', 3, 7), @('  ▝▝ ▝▝  ', 0, 0))
    'right-75' = @(@('   ██▛▌  ', 3, 6), @('   ███▌  ', 3, 6), @('   ▘  ▘  ', 0, 0))
    'edge'     = @(@('   ▐██   ', 4, 6), @('   ▐██   ', 4, 6), @('   ▝ ▝   ', 0, 0))
    'back-105' = @(@('   ███▌  ', 3, 6), @('   ███▌  ', 3, 6), @('   ▘  ▘  ', 0, 0))
    'back-125' = @(@('  ▐████  ', 3, 7), @('  ▐████  ', 3, 7), @('  ▝▝ ▝▝  ', 0, 0))
    'back-150' = @(@('  █████▌ ', 2, 7), @(' ▝█████▛ ', 2, 7), @('  ▘▘  ▘▘ ', 0, 0))
    'back'     = @(@(' ▐██████ ', 2, 8), @('▝▜██████▀', 2, 7), @(' ▝▝   ▝▝ ', 0, 0))
    'left-75'  = @(@('   ▛██▌  ', 3, 6), @('   ███▌  ', 3, 6), @('   ▘  ▘  ', 0, 0))
    'left-55'  = @(@('  ▐▜▛██  ', 3, 7), @('  ▐████  ', 3, 7), @('  ▝▝ ▝▝  ', 0, 0))
    'left-30'  = @(@('  ▛██▛█▌ ', 2, 7), @(' ▝█████▛ ', 2, 7), @('  ▘▘  ▘▘ ', 0, 0))
    'left-12'  = @(@(' ▐▛███▜█ ', 2, 8), @('▝▜██████▀', 2, 7), @(' ▝▝   ▝▝ ', 0, 0))
}

# Eyes: black pixels "dx,dy" from the top-left corner of the eye cell
# (columns 2 and 6 of the first row). With ";" - left and right eye separately.
# open/left/right/closed/wink - exactly as in Claude Code, the rest are custom.
$EyeShapes = @{
    open   = '1,2 1,3'                             # normal
    left   = '0,0 0,1'                             # looking left
    right  = '2,0 2,1'                             # looking right
    closed = '0,3 1,3'                             # eyelid line, asleep
    blink  = '0,3 1,3'                             # blink
    wink   = '1,2 1,3;0,3 1,3'                     # wink
    happy  = '0,3 1,2 2,3'                         # happy ^ ^
    focus  = '1,3'                                 # focused squint
    wide   = '0,1 1,1 0,2 1,2 0,3 1,3'             # wide open
    x      = '0,1 2,1 1,2 0,3 2,3'                 # crosses
    yawn   = '0,3 1,3'                             # yawning (mouth drawn separately)
    gasp   = '0,1 2,1 1,2 0,3 2,3'                 # crosses with open mouth - soul leaving
}

# Names - T "mood.<id>" and T "act.<id>".
$MascotMoods = @('sleep', 'doze', 'idle', 'work', 'wait', 'dead')

# ----------------------------------------------- animations from Claude Code ----
# Frame - pose plus offset: off - rows lowered by (1 - crouched, legs
# hidden; 3 - fully hidden; negative - above the frame), x - shift in cells,
# poof - dust puffs at the sides when crouching, shadow - shadow in the coin hop.
# Anything outside the 9x3 frame is clipped, as in the terminal. Frame - 60 ms.
$ClawdFrameMs = 60
$ClawdPoses = @{
    'default'    = 'open/down/both'
    'arms-up'    = 'open/up/both'
    'look-left'  = 'left/down/both'
    'look-right' = 'right/down/both'
}
function New-ClawdFrames([string]$pose, [int]$n = 1, [int]$off = 0, [int]$x = 0,
                         [string]$poof = '', [string]$shadow = '') {
    $fr = @{ off = $off; x = $x; poof = $poof; shadow = $shadow; facing = '' }
    if ($pose.StartsWith('face:')) {
        $fr.facing = $pose.Substring(5)
        $fr.eyes = 'open'; $fr.arms = 'down'; $fr.feet = 'both'
    } else {
        if ($ClawdPoses.ContainsKey($pose)) { $pose = $ClawdPoses[$pose] }
        $fr.eyes, $fr.arms, $fr.feet = $pose.Split('/')
    }
    , @(for ($i = 0; $i -lt $n; $i++) { $fr })
}
function F { New-ClawdFrames @args }
$cr = (F default 1 -off 1 -poof dot) + (F default 1 -off 1 -poof wave)   # crouch before the jump
$bo = F default                                                           # rest
$ts = (F 'closed/down/both') + $bo                                        # blink at the end
function Get-ClawdTurn([string[]]$list, [string]$shadow = '') {
    $r = @(); foreach ($p in $list) { $r += F "face:$p" 1 -shadow $shadow }; , $r
}

$jumpSeq = $cr + (F arms-up 3) + $bo + $cr + (F arms-up 3) + $bo
$waddle  = F look-right 1 -x -9
foreach ($u in -6..-1) {
    $waddle += F "right/down/$(if ($u % 2 -eq 0) { 'left' } else { 'right' })" 2 -x $u
}
$ClawdSeqs = [ordered]@{
    jump      = $jumpSeq
    look      = (F look-right 5) + (F look-left 5) + $bo
    celebrate = $jumpSeq + (F default 3 -off 1)
    skip      = (F default 1 -off 1 -x -9) + (F arms-up 2 -x -6) + (F default 1 -x -6) +
                (F default 1 -off 1 -x -6) + (F arms-up 2 -x -3) + (F default 1 -x -3) +
                (F default 1 -off 1 -x -3) + (F arms-up 2) + $cr + $bo
    spin      = (F look-left 2) + (F look-right 2) + (F look-left 2) + (F arms-up 3) + $bo
    peekaboo  = (F default 1 -off 3) + (F default 3 -off 2) + (F look-right 3 -off 2) +
                (F look-left 3 -off 2) + (F default 2 -off 2) + (F default 1 -off 1) +
                (F arms-up 4) + (F default 2) + $ts
    drop      = (F arms-up 1 -off -3) + (F arms-up 2 -off -2) + (F arms-up 2 -off -1) +
                (F arms-up 1) + $cr + (F default 3) + $ts
    waddle    = $waddle + (F look-right 2) + (F default 2) + $ts
    peek      = (F look-right 1 -x -9) + (F look-right 5 -x -6) + (F look-right 3 -x -9) +
                (F look-right 4 -x -5) + (F arms-up 2 -x -3) + (F arms-up 2) + $cr + $bo
    wink      = (F 'wink/down/both' 5) + $bo
    boop      = (F 'closed/down/both' 1 -off 1 -poof dot) + (F 'closed/down/both' 2 -off 1 -poof wave) +
                (F look-left 4) + (F default 2) + $ts
    tap       = (F 'open/down/left' 2) + (F 'open/down/right' 2) + (F 'open/down/left' 2) +
                (F 'open/down/right' 2) + (F 'open/down/left' 1) + (F 'open/down/right' 1) +
                (F arms-up 3) + $bo
    sneeze    = (F 'closed/up/both' 4) + (F 'closed/down/both' 2 -off 1 -poof wave) +
                (F 'closed/down/both' 2) + (F default 2) + $ts
    turn      = (Get-ClawdTurn 'right-12', 'right-30', 'right-55', 'right-75', 'edge') +
                (Get-ClawdTurn 'back-105', 'back-125', 'back-150', 'back', 'back') +
                (Get-ClawdTurn 'back-150', 'back-125', 'back-105', 'edge') +
                (Get-ClawdTurn 'left-75', 'left-55', 'left-30', 'left-12') + $bo
    'coin-hop' = (F default 2 -off 1) + (F arms-up 1 -shadow wide) +
                 (Get-ClawdTurn 'right-55', 'edge', 'back-125', 'back' 'narrow') +
                 (Get-ClawdTurn 'back-125', 'edge', 'left-55' 'narrow') +
                 (F arms-up 1 -shadow wide) + $cr + $bo
}
Remove-Item Function:\F
# On click - as in Claude Code: everything that starts in place (no slide-in).
$ClawdClickActs = @($ClawdSeqs.Keys | Where-Object { $ClawdSeqs[$_][0].x -eq 0 -and $_ -ne 'celebrate' })
# On widget start - entrance from any animation, as on first launch of a new version.
$ClawdEntranceActs = @($ClawdSeqs.Keys | Where-Object { $_ -ne 'celebrate' })

$MascotActs = [ordered]@{
    jump       = @{}
    look       = @{}
    celebrate  = @{}
    skip       = @{}
    spin       = @{}
    peekaboo   = @{}
    drop       = @{}
    waddle     = @{}
    peek       = @{}
    wink       = @{}
    boop       = @{}
    tap        = @{}
    sneeze     = @{}
    turn       = @{}
    'coin-hop' = @{}
    wave       = @{ len = 24 }
    stretch    = @{ len = 22 }
    yawn       = @{ len = 22 }
    stumble    = @{ len = 20 }
    soul       = @{ len = 66 }
    # Burrow: the demo shows these via sleep transitions, not needed separately.
    burrow     = @{ len = 30; noDemo = $true }
    unburrow   = @{ len = 28; noDemo = $true }
    stir       = @{ len = 22; noDemo = $true }
}
foreach ($id in $ClawdSeqs.Keys) { $MascotActs[$id].len = $ClawdSeqs[$id].Count }

# Order of display in the demo from the developer menu.
$MascotDemo = @(
    @{ kind = 'mood'; id = 'sleep' }, @{ kind = 'mood'; id = 'doze' },
    @{ kind = 'mood'; id = 'idle' },  @{ kind = 'mood'; id = 'work' },
    @{ kind = 'crit'; id = 'work' },  @{ kind = 'mood'; id = 'wait' },
    @{ kind = 'drain'; id = 'idle' }
) + @($MascotActs.Keys | Where-Object { -not $MascotActs[$_].noDemo } |
        ForEach-Object { @{ kind = 'act'; id = $_ } })

# Burrow: dig - pixel rows sunk into the sand (4 - top of the head and
# eyes stick out), spray - phase of sand grains flying from the legs (0 - none).
$BurrowDig = 4

# Frame $f: eyes, arms, feet, look, flip, off, x, facing, poof, shadow, dig, spray.
function Get-MascotGeo($f) {
    $key = "$($script:Skin.id)|$($f.eyes)|$($f.arms)|$($f.feet)|$($f.look)|$($f.flip)|$($f.off)|$($f.x)|$($f.facing)|$($f.poof)|$($f.shadow)|$($f.dig)|$($f.spray)"
    if ($script:MascotGeo.ContainsKey($key)) { return $script:MascotGeo[$key] }

    $W = 2 * $ClawdCols; $H = 4 * $ClawdRows
    # 0 - empty, 1 - body, 2 - black (eyes and face).
    $g = New-Object 'int[,]' $W, $H
    # Glyphs into cells: mode 'eyes' - black background, 'lid' - black glyph on body color.
    $paint = {
        param([string]$glyphs, [int]$col, [int]$row, [string]$mode)
        for ($i = 0; $i -lt $glyphs.Length; $i++) {
            $c = $glyphs[$i]
            $fg = $(if ($mode -eq 'lid') { 2 } else { 1 })
            $bg = $(switch ($mode) { 'eyes' { 2 } 'lid' { 1 } default { 0 } })
            for ($sy = 0; $sy -lt 4; $sy++) {
                for ($sx = 0; $sx -lt 2; $sx++) {
                    if ($c -eq '▂') { $on = $sy -eq 3 }
                    else {
                        $bit = $(if ($sy -lt 2) { 1 } else { 4 }) * $(if ($sx) { 2 } else { 1 })
                        $on = [bool]($ClawdQuad[$c] -band $bit)
                    }
                    $v = $(if ($on) { $fg } else { $bg })
                    if ($v) { $g[(2 * ($col + $i) + $sx), (4 * $row + $sy)] = $v }
                }
            }
        }
    }

    if ($f.facing) {
        foreach ($r in 0..2) {
            $s, $from, $to = $ClawdFacing[$f.facing][$r]
            & $paint $s.Substring(0, $from) 0 $r ''
            & $paint $s.Substring($from, $to - $from) $from $r 'eyes'
            & $paint $s.Substring($to) $to $r ''
        }
    } else {
        $a = $ClawdArms[$f.arms]
        & $paint $a.r1L 0 0 ''
        & $paint '██████' 2 0 'eyes'
        & $paint $a.r1R 8 0 ''
        & $paint $a.r2L 0 1 ''
        & $paint '█████' 2 1 'eyes'
        & $paint $a.r2R 7 1 ''
        & $paint $ClawdFeet[$f.feet] 0 2 ''

        # Looking sideways with normal eyes - ready-made Claude Code poses,
        # for other expressions just shift the pupils.
        $eyes = $f.eyes; $shift = 0
        if ($eyes -eq 'open' -and $f.look -lt 0) { $eyes = 'left' }
        elseif ($eyes -eq 'open' -and $f.look -gt 0) { $eyes = 'right' }
        elseif ($eyes -notin @('open', 'left', 'right', 'wink')) { $shift = [int]$f.look }
        $sh = $EyeShapes[$eyes].Split(';')
        $ex = @(4, 12)
        for ($k = 0; $k -lt 2; $k++) {
            foreach ($pt in $sh[[math]::Min($k, $sh.Count - 1)].Split(' ')) {
                $dx, $dy = $pt.Split(',')
                $g[($ex[$k] + [int]$dx + $shift), [int]$dy] = 2
            }
        }
        # Yawn: squeezed-shut eyes plus an open mouth.
        if ($eyes -in @('yawn', 'gasp')) { foreach ($x in 8..10) { $g[$x, 4] = 2; $g[$x, 5] = 2 } }
    }

    $body = New-Object System.Windows.Media.GeometryGroup
    $eyeG = New-Object System.Windows.Media.GeometryGroup
    $fx   = New-Object System.Windows.Media.GeometryGroup
    $sand = New-Object System.Windows.Media.GeometryGroup
    # Lowered by off rows and shifted by x cells; anything outside the frame is clipped.
    # What sank into the burrow is clipped at the ground - the edge of the empty lower half-row.
    $oy = 4 * [int]$f.off + [int]$f.dig; $ox = 2 * [int]$f.x
    $lim = $(if ([int]$f.dig -gt 0) { $H - 2 } else { $H })
    for ($y = 0; $y -lt $H; $y++) {
        # Flipped - lying on its back, legs up (the empty lower half-row does not count).
        $sy = $y
        if ($f.flip) { if ($y -ge $H - 2) { continue } else { $sy = $H - 3 - $y } }
        $yy = $sy + $oy
        if ($yy -lt 0 -or $yy -ge $lim) { continue }
        $x = 0
        while ($x -lt $W) {
            $c = $g[$x, $y]
            if (-not $c) { $x++; continue }
            # Merge adjacent same-color pixels into one rectangle.
            $x0 = $x
            while ($x -lt $W -and $g[$x, $y] -eq $c) { $x++ }
            $l = [math]::Max(0, $x0 + $ox); $rr = [math]::Min($W, $x + $ox)
            if ($rr -le $l) { continue }
            $rect = [System.Windows.Rect]::new($l * $MascotPx, $yy * $MascotPy,
                                               ($rr - $l) * $MascotPx, $MascotPy)
            $rg = [System.Windows.Media.RectangleGeometry]::new($rect)
            if ($c -eq 2) { $eyeG.Children.Add($rg) } else { $body.Children.Add($rg) }
        }
    }
    # Skin accessories (skins.ps1), in Clawd's pixels: rows above his head are negative.
    # Above the head - while the head is in the frame; on the body - like the body.
    # Turning, only what is above the head stays; on his back he loses them all.
    $acc = @()
    foreach ($l in @($script:Skin.layers)) {
        $gg = New-Object System.Windows.Media.GeometryGroup
        if (-not $f.flip) {
            foreach ($pt in $l.px) {
                $x = [int]$pt[0] + $ox; $y = [int]$pt[1]
                if ($y -ge 0 -and $f.facing) { continue }
                $yy = $y + $oy
                if ($x -lt 0 -or $x -ge $W -or $yy -ge $lim) { continue }
                if ($(if ($y -lt 0) { $oy -lt 0 } else { $yy -lt 0 })) { continue }
                $gg.Children.Add([System.Windows.Media.RectangleGeometry]::new(
                    [System.Windows.Rect]::new($x * $MascotPx, $yy * $MascotPy, $MascotPx, $MascotPy)))
            }
        }
        $gg.Freeze()
        $acc += $gg
    }
    # Dust "·" and "~" at the edges of the bottom row while crouched.
    if ($f.poof -and $f.off -gt 0) {
        foreach ($cx in @(0, ($W - 2))) {
            if ($f.poof -eq 'dot') { $pts = @(@(0.6, 9.4, 0.8, 0.9)) }
            else { $pts = @(@(0.0, 9.6, 0.7, 0.6), @(0.7, 9.1, 0.6, 0.6), @(1.3, 9.6, 0.7, 0.6)) }
            foreach ($p in $pts) {
                $fx.Children.Add([System.Windows.Media.RectangleGeometry]::new(
                    [System.Windows.Rect]::new(($cx + $p[0]) * $MascotPx, $p[1] * $MascotPy,
                                               $p[2] * $MascotPx, $p[3] * $MascotPy)))
            }
        }
    }
    # Shadow "▁" under the hopping coin.
    if ($f.shadow) {
        $sc, $sw = $(if ($f.shadow -eq 'wide') { 6, 6 } else { 8, 2 })
        $fx.Children.Add([System.Windows.Media.RectangleGeometry]::new(
            [System.Windows.Rect]::new($sc * $MascotPx, ($H - 0.5) * $MascotPy, $sw * $MascotPx, 0.5 * $MascotPy)))
    }
    # Sand mound over the burrow: a strip along the ground and piles at the sides where dug.
    $px = { param([double]$x, [double]$y, [double]$w, [double]$h)
        $sand.Children.Add([System.Windows.Media.RectangleGeometry]::new(
            [System.Windows.Rect]::new($x * $MascotPx, $y * $MascotPy, $w * $MascotPx, $h * $MascotPy)))
    }
    $dig = [int]$f.dig
    if ($dig -ge 1) { & $px -2 ($H - 3) ($W + 4) 1 }
    if ($dig -ge 2) { & $px -1 ($H - 4) ($W + 2) 1 }
    if ($dig -ge 3) { & $px -1 ($H - 5) 2 1; & $px ($W - 1) ($H - 5) 2 1 }
    # Sand grains fly in an arc from under the legs to both sides.
    if ([int]$f.spray -gt 0) {
        $s = [int]$f.spray
        foreach ($k in @(0, 1)) {
            $d  = $s + 2 * $k
            $sx = 1.5 + 0.9 * $d; $sy = ($H - 4) - 0.9 * $d * (5 - $d) / 2
            & $px (-$sx) $sy 0.8 0.8
            & $px ($W - 0.8 + $sx) $sy 0.8 0.8
        }
    }
    $body.Freeze(); $eyeG.Freeze(); $fx.Freeze(); $sand.Freeze()
    $geo = @{ body = $body; eyes = $eyeG; fx = $fx; sand = $sand; acc = $acc }
    $script:MascotGeo[$key] = $geo
    return $geo
}

$script:Rnd = New-Object System.Random
$script:Mz  = @{
    x = -1.0; dir = 1; target = $null; look = 0
    tick = 0; blinkAt = 30; key = ''
    mood = 'idle'; crit = $false; idleSince = (Get-Date)
    act = $null; actT = 0
    force = $null; forceCrit = $false; demo = -1; demoT = 0
    pct = $null; halves = $null; heartsKey = ''; lostT = -1; lostFrom = 0
    forceHearts = $null; drainT = -1; loveT = -1; noteT = -1; confT = -1
    busy = -1; waiting = 0; lastReset = $null; lastPct = $null
    broken = $false; buried = $false
}

function Start-MascotAct([string]$name) {
    $script:Mz.act  = $name
    $script:Mz.actT = 0
    if ($name -eq 'celebrate') { Start-Confetti }
}

# Click on the mascot - a random Claude Code animation and a heart, if it is
# free. Lying with the limit exhausted - its soul leaves the body instead.
function Start-MascotClick {
    $m = $script:Mz
    if ($m.mood -eq 'dead' -or $m.cur -eq 'dead') {
        if (-not $m.act) { Start-MascotAct 'soul' }
        return
    }
    $m.loveT = 0
    # Asleep in the burrow - does not come out, just opens its eyes and looks around.
    if ($m.buried -and $m.cur -eq 'sleep') {
        if (-not $m.act) { Start-MascotAct 'stir' }
        return
    }
    if ($m.act) { return }
    Start-MascotAct $ClawdClickActs[$script:Rnd.Next($ClawdClickActs.Count)]
}

# Soul - a translucent mini-Clawd with a tail, a thread runs to the mouth.
$SoulUp   = 26     # frame when the soul reaches the top
$SoulBack = 48     # frame when it starts being sucked back
$SoulTop  = 20.0   # height above the mouth
$SoulPx   = 1.4
$SoulArt  = @(
    '..########..'
    '..#.####.#..'
    '############'
    '..########..'
    '...######...'
    '....####....'
    '.....##.....'
)
# Geometry with the origin at the mouth: soul at height $h, sways and pulls the thread.
function Get-SoulGeo([double]$h, [int]$t) {
    $g  = New-Object System.Windows.Media.GeometryGroup
    $p  = $SoulPx
    $sway = 2.5 * [math]::Sin($t / 4.0)
    $add = { param($x, $y, $w) $g.Children.Add([System.Windows.Media.RectangleGeometry]::new([System.Windows.Rect]::new($x, $y, $w, $p))) }
    # Thread: from the mouth to the soul's tail, wiggles and smoothly follows the sway.
    $n = [math]::Floor($h / $p)
    for ($i = 0; $i -lt $n; $i++) {
        $k  = $i / [math]::Max(1, $n)
        $dx = $sway * $k + 1.2 * [math]::Sin($t / 2.0 + $i * 0.7) * [math]::Sin($k * [math]::PI)
        & $add ([math]::Round($dx / $p) * $p - $p / 2) (-($i + 1) * $p) $p
    }
    $top = -$h - $SoulArt.Count * $p
    $x0  = [math]::Round($sway / $p) * $p - 6 * $p
    for ($y = 0; $y -lt $SoulArt.Count; $y++) {
        $row = $SoulArt[$y]; $x = 0
        while ($x -lt $row.Length) {
            if ($row[$x] -ne '#') { $x++; continue }
            $a = $x
            while ($x -lt $row.Length -and $row[$x] -eq '#') { $x++ }
            & $add ($x0 + $a * $p) ($top + $y * $p) (($x - $a) * $p)
        }
    }
    $g.Freeze()
    return $g
}

# Particles are drawn right in the mascot area: confetti on celebration, dust when running.
function New-Particle([double]$w, [double]$h, [string]$color) {
    $r = New-Object System.Windows.Shapes.Rectangle
    $r.Width = $w; $r.Height = $h
    $r.Fill = New-Brush $color
    $r.IsHitTestVisible = $false
    $r.Visibility = 'Collapsed'
    $UI.MascotArea.Children.Add($r) | Out-Null
    return $r
}

$ConfettiColors = @('#FFF87171', '#FFFBBF24', '#FF4ADE80', '#FF60A5FA', '#FFA78BFA', '#FFD77757')
$script:Confetti = @()
for ($i = 0; $i -lt 12; $i++) {
    $script:Confetti += @{ r = (New-Particle 2 2.5 $ConfettiColors[$i % $ConfettiColors.Count]); x = 0.0; y = 0.0; v = 0.0; d = 0.0 }
}
$script:Dust = @()
for ($i = 0; $i -lt 3; $i++) { $script:Dust += (New-Particle 2 2 '#FF8B8B94') }

function Start-Confetti {
    $m = $script:Mz
    foreach ($c in $script:Confetti) {
        $c.x = $m.x - 12 + $script:Rnd.NextDouble() * ($MascotW + 24)
        $c.y = 34 + $script:Rnd.NextDouble() * 12
        $c.v = 0.9 + $script:Rnd.NextDouble() * 1.2
        $c.d = ($script:Rnd.NextDouble() - 0.5) * 0.8
    }
    $m.confT = 0
}
function Set-MascotMood($ss, $real) {
    $m = $script:Mz
    $busy    = @($ss | Where-Object { $_.busy }).Count
    $waiting = @($ss | Where-Object { $_.waiting }).Count
    $pct     = $null
    if ($real) { $pct = $real.session }

    if ($null -ne $pct -and $pct -ge 100) { $mood = 'dead' }
    elseif ($waiting)                     { $mood = 'wait' }
    elseif ($busy)                        { $mood = 'work' }
    elseif (@($ss).Count)                 { $mood = 'idle' }
    else                                  { $mood = 'sleep' }
    if ($mood -ne $m.mood) { $m.idleSince = Get-Date }
    $m.mood = $mood

    # A session finished its reply (rather than stopping to wait for us) - jump.
    if ($m.busy -gt 0 -and $busy -lt $m.busy -and $waiting -le $m.waiting -and -not $m.act) {
        Start-MascotAct 'jump'
    }
    $m.busy    = $busy
    $m.waiting = $waiting
    $m.crit    = $null -ne $pct -and (Get-Level $pct) -eq 'crit'
    $m.pct     = $pct

    # The 5-hour window reset: reset time moved forward, percent dropped - celebrate.
    if ($real -and $real.sessionReset) {
        if ($m.lastReset -and $real.sessionReset -gt $m.lastReset -and
            $null -ne $m.lastPct -and $pct -lt $m.lastPct) {
            Start-MascotAct 'celebrate'
        }
        $m.lastReset = $real.sessionReset
        $m.lastPct   = $pct
    }
}

# Where to look if the cursor is over the window: -1/0/1, or $null if there is no cursor.
function Get-MouseLook {
    if (-not $win.IsMouseOver) { return $null }
    $mx = [System.Windows.Input.Mouse]::GetPosition($UI.MascotArea).X
    $cx = $script:Mz.x + $MascotW / 2
    if ($mx -gt $cx + 10) { return 1 }
    if ($mx -lt $cx - 10) { return -1 }
    return 0
}


# One-shot animation frame; returns the speech bubble text above the head.
function Step-MascotAct($f) {
    $m = $script:Mz
    $t = $m.actT
    $bubble = ''
    if ($ClawdSeqs.Contains($m.act)) {
        # Claude Code animations - frame by frame, the pose itself sets the gaze.
        $fr = $ClawdSeqs[$m.act][$t]
        foreach ($k in 'eyes', 'arms', 'feet', 'off', 'x', 'facing', 'poof', 'shadow') { $f[$k] = $fr[$k] }
        $f.look = 0
        if ($m.act -eq 'celebrate') { $bubble = '!' }
    } else {
        switch ($m.act) {
            'wave' {
                $f.look = 0; $f.eyes = 'happy'
                $f.arms = $(if ([math]::Floor($t / 4) % 2) { 'down' } else { 'right' })
            }
            'stretch' {
                if ($t -ge 4 -and $t -lt 18) { $f.arms = 'up'; $f.eyes = 'closed'; $f.lift = 1.5 }
            }
            'yawn' {
                $f.look = 0
                if ($t -ge 3 -and $t -lt 17) { $f.eyes = 'yawn' } else { $f.eyes = 'closed' }
            }
            'stumble' {
                # Flops down (crouched, legs hidden), then gets up and stares, stunned.
                if ($t -lt 12) { $f.off = 1; $f.eyes = 'closed' } else { $f.eyes = 'wide' }
                $f.look = 0
            }
            'soul' {
                # Like in anime: the soul flies out of the open mouth on a thread, hangs over
                # the body, then gets sucked back in - and the body twitches.
                $f.flip = $true; $f.look = 0
                if ($t -lt 6) {
                    $f.eyes = 'x'
                    $f.feet = $(if ($t % 2) { 'left' } else { 'right' })
                } elseif ($t -lt $SoulBack + 6) {
                    $f.eyes = 'gasp'
                    $f.soulT = $t
                    if ($t -lt $SoulUp) {
                        $k = ($t - 6) / ($SoulUp - 6.0)
                        $f.soul = $SoulTop * (1 - (1 - $k) * (1 - $k))       # floats out, slowing down
                    } elseif ($t -lt $SoulBack) {
                        $f.soul = $SoulTop + 1.5 * [math]::Sin(($t - $SoulUp) / 2.5)
                    } else {
                        $k = ($t - $SoulBack) / 6.0
                        $f.soul = $SoulTop * (1 - $k * $k)                   # snaps back in
                    }
                } elseif ($t -lt $SoulBack + 9) {
                    $f.eyes = 'wide'; $f.lift = 2.5                          # wakes for a moment
                } else {
                    $f.eyes = 'x'
                }
            }
            'burrow' {
                # Looks around, digs with its legs sinking into the sand, and closes its eyes.
                if ($t -lt 4) {
                    $f.look = $(if ($t -lt 2) { -1 } else { 1 })
                } elseif ($t -lt 24) {
                    $f.look = 0; $f.eyes = 'focus'
                    $f.dig   = [math]::Min($BurrowDig, [math]::Floor(($t - 4) / 3.5))
                    $f.feet  = $(if ([math]::Floor($t / 2) % 2) { 'left' } else { 'right' })
                    $f.arms  = $(if ([math]::Floor($t / 2) % 2) { 'up' } else { 'down' })
                    $f.spray = ($t % 3) + 1
                } else {
                    $f.look = 0; $f.dig = $BurrowDig
                    $f.eyes = $(if ($t -lt 27) { 'blink' } else { 'closed' })
                }
            }
            'unburrow' {
                # Eyes wide, jumps out of the sand and shakes itself off.
                $f.look = 0
                if ($t -lt 3) {
                    $f.dig = $BurrowDig; $f.eyes = 'wide'
                } elseif ($t -lt 9) {
                    $f.dig = [math]::Max(0, $BurrowDig - ($t - 3)); $f.eyes = 'wide'
                    $f.arms = 'up'; $f.spray = ($t % 3) + 1
                    if ($t -eq 8) { $f.lift = 2 }
                } elseif ($t -lt 21) {
                    $f.eyes = 'closed'
                    $f.look = $(if ([math]::Floor($t / 2) % 2) { -1 } else { 1 })
                    $f.feet = $(if ([math]::Floor($t / 2) % 2) { 'left' } else { 'right' })
                    if ($t -lt 15) { $f.spray = ($t % 3) + 1 }
                } elseif ($t -lt 23) {
                    $f.eyes = 'blink'
                }
            }
            'stir' {
                # Rises in the burrow, looks around and sinks back into the sand.
                $f.dig = $(if ($t -lt 15) { $BurrowDig - 1 } else { $BurrowDig })
                if ($t -lt 3)      { $f.eyes = 'wide'; $f.look = 0 }
                elseif ($t -lt 13) { $f.look = $(if ($t -lt 8) { -1 } else { 1 }) }
                elseif ($t -lt 17) { $f.eyes = 'blink'; $f.look = 0 }
                else               { $f.eyes = 'closed'; $f.look = 0 }
            }
        }
    }
    $m.actT++
    if ($m.actT -ge $MascotActs[$m.act].len) { $m.act = $null }
    return $bubble
}

# Entrance on widget start.
Start-MascotAct $ClawdEntranceActs[$script:Rnd.Next($ClawdEntranceActs.Count)]
