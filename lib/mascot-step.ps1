function Stop-MascotDemo {
    $m = $script:Mz
    $m.demo = -1; $m.demoT = 0
    $m.force = $null; $m.forceCrit = $false; $m.act = $null
    if ($m.drainT -ge 0) { $m.drainT = -1; $m.forceHearts = $null }
}

function Step-MascotDemo {
    $m = $script:Mz
    $s = $MascotDemo[$m.demo]
    if ($m.demoT -eq 0) {
        $m.forceCrit = $false
        switch ($s.kind) {
            'mood'  { $m.force = $s.id; $m.act = $null }
            'crit'  { $m.force = $s.id; $m.act = $null; $m.forceCrit = $true }
            'act'   { $m.force = 'idle'; $m.target = $null; Start-MascotAct $s.id }
            'drain' { $m.force = 'work'; $m.act = $null; $m.drainT = 0 }
        }
    }
    $m.demoT++
    $len = switch ($s.kind) {
        'act'   { $MascotActs[$s.id].len + 12 }
        'drain' { $DrainLen + 10 }
        default { 55 }
    }
    if ($m.demoT -ge $len) {
        $m.demoT = 0
        $m.demo++
        if ($m.demo -ge $MascotDemo.Count) { Stop-MascotDemo }
    }
}

function Step-Mascot {
    $m = $script:Mz
    $m.tick++
    $span = [math]::Max(0, $UI.MascotArea.ActualWidth - $MascotW)
    if ($m.x -lt 0)     { $m.x = $span / 2 }
    if ($m.x -gt $span) { $m.x = $span }

    if ($m.demo -ge 0) { Step-MascotDemo }
    if ($m.drainT -ge 0) {
        $m.forceHearts = [math]::Max(0, 6 - [math]::Floor($m.drainT / $DrainStep))
        $m.drainT++
        if ($m.drainT -ge $DrainLen) { $m.drainT = -1; $m.forceHearts = $null }
    }
    $mood = $(if ($m.force) { $m.force } else { $m.mood })
    # Zero hearts - always lies down, including when set manually.
    if ($null -ne $m.forceHearts -and [int]$m.forceHearts -eq 0) { $mood = 'dead' }
    # Health from hearts; no data - "fine".
    $halves = Get-Halves
    $tierN  = $(if ($null -eq $halves) { 5 } else { $halves })
    $tier   = $HealthTiers[$tierN]
    $perky  = $tier.speed -ge 0.9   # lively enough to jump and whistle
    $now  = Get-Date
    # Cursor over the window wakes him; long silence - dozes standing up.
    if ($win.IsMouseOver) { $m.idleSince = $now }
    if ($mood -eq 'idle' -and -not $m.force -and ($now - $m.idleSince).TotalMinutes -ge 10) { $mood = 'doze' }

    # Falling asleep - burrows into the sand once the current animation finishes;
    # waking up - climbs out of the burrow at once, whatever is playing.
    if ($mood -eq 'sleep') {
        if (-not $m.buried -and -not $m.act) { $m.buried = $true; Start-MascotAct 'burrow' }
    } elseif ($m.buried) {
        $m.buried = $false
        Start-MascotAct 'unburrow'
    }

    $f = @{ feet = 'both'; look = $m.look; eyes = 'open'; arms = 'down'; flip = $false; lift = 0.0
           off = 0; x = 0; facing = ''; poof = ''; shadow = ''; soul = 0.0; soulT = 0; dig = 0; spray = 0 }
    $m.cur = $mood
    $bubble = ''; $zzz = $false; $canBlink = $true; $dust = $false

    if ($m.act) {
        $bubble   = Step-MascotAct $f
        $canBlink = $false
    } else {
        switch ($mood) {
            'sleep' { $f.dig = $BurrowDig; $f.eyes = 'closed'; $f.look = 0; $zzz = $true }
            'doze'  {
                # Nods off, and sometimes startles and goggles.
                $f.look = 0
                $p = $m.tick % 70
                if ($p -lt 6) {
                    $f.eyes = 'wide'
                    if ($p -lt 2) { $f.lift = 1.5 }
                } else {
                    $f.eyes = 'blink'; $zzz = $true
                }
            }
            'dead'  {
                $f.flip = $true; $f.eyes = 'x'; $f.look = 0
                # Occasionally twitches his legs.
                $p = $m.tick % 50
                if ($p -lt 6) { $f.feet = $(if ($p % 2) { 'left' } else { 'right' }) }
            }
            'wait'  {
                $bubble = '?'; $f.eyes = 'wide'
                $ml = Get-MouseLook
                $f.look = $(if ($null -ne $ml) { $ml } else { 0 })
                # Jumps and waves: hey, someone is waiting for you.
                $p = $m.tick % 40
                if ($p -lt 8) {
                    $k = $p / 7.0
                    $f.lift = 12 * $k * (1 - $k)
                    $f.arms = 'right'
                }
            }
            default {
                if ($mood -eq 'work') {
                    $speed = 1.6 * $tier.speed
                    # Runs from edge to edge.
                    if ($null -eq $m.target) { $m.target = $(if ($m.dir -gt 0) { $span } else { 0.0 }) }
                } else {
                    $speed = 0.6 * $tier.speed
                    if ($null -eq $m.target) {
                        if ($script:Rnd.Next(70) -eq 0)     { $m.target = $script:Rnd.NextDouble() * $span }
                        elseif ($script:Rnd.Next(45) -eq 0) { $m.look = $script:Rnd.Next(-1, 2) }
                        elseif ($script:Rnd.Next(400) -eq 0) {
                            Start-MascotAct (@('wave', 'stretch', 'look')[$script:Rnd.Next(3)])
                        }
                    }
                }
                $walking = $false
                if ($null -ne $m.target) {
                    $d = $m.target - $m.x
                    if ([math]::Abs($d) -le $speed) {
                        $m.x = $m.target; $m.target = $null
                        if ($mood -eq 'work') { $m.dir = -$m.dir }
                    } else {
                        $m.dir   = [math]::Sign($d)
                        $m.x    += $speed * $m.dir
                        $m.look  = $m.dir
                        $walking = $true
                    }
                }
                if ($walking) {
                    # The less energy, the slower the steps.
                    $step = $(if ($mood -eq 'work') { 2 } else { 3 })
                    if ($tier.speed -lt 0.8) { $step++ }
                    if ($tier.speed -lt 0.5) { $step++ }
                    $f.feet = $(if ([math]::Floor($m.tick / $step) % 2) { 'left' } else { 'right' })
                    if ($mood -eq 'work') {
                        if ($f.feet -eq 'left' -and $perky) { $f.lift = 1 }
                        $dust = $true
                        if ($perky -and $script:Rnd.Next(150) -eq 0) { Start-MascotAct 'jump' }
                    } elseif ($perky -and $m.noteT -lt 0 -and $script:Rnd.Next(80) -eq 0) {
                        $m.noteT = 0   # whistles while walking
                    }
                    if ($tier.stumble -and $script:Rnd.Next($tier.stumble) -eq 0) { Start-MascotAct 'stumble' }
                } elseif ($m.crit -or $m.forceCrit) {
                    # Limit running out - eyes dart nervously.
                    $m.look = $(if ([math]::Floor($m.tick / 5) % 2) { -1 } else { 1 })
                } else {
                    # Standing - follows the cursor.
                    $ml = Get-MouseLook
                    if ($null -ne $ml) { $m.look = $ml }
                }
                $f.look = $m.look
                if ($mood -eq 'work') { $f.eyes = 'focus' }
                # Full of energy - jumps for joy; tired - yawns.
                if (-not $m.act) {
                    if ($tier.hop -and $script:Rnd.Next($tier.hop) -eq 0)   { Start-MascotAct 'jump' }
                    if ($tier.yawn -and $script:Rnd.Next($tier.yawn) -eq 0) { Start-MascotAct 'yawn' }
                }
            }
        }
    }

    # Tired eyes on top of the normal and working ones.
    if ($tier.eyes -and -not $m.act -and $f.eyes -in @('open', 'focus')) { $f.eyes = $tier.eyes }

    # Petted - pleased.
    if ($m.loveT -ge 0 -and -not $m.act -and $f.eyes -eq 'open') { $f.eyes = 'happy' }
    # Whistling: notes, if there are no other bubbles.
    if ($m.noteT -ge 0) {
        if (-not $bubble -and $mood -eq 'idle') { $bubble = [string][char]0x266A }
        $m.noteT++
        if ($m.noteT -ge 30) { $m.noteT = -1 }
    }

    if ($canBlink -and $f.eyes -eq 'open' -and $m.tick -ge $m.blinkAt) {
        $f.eyes = 'blink'
        if ($m.tick -ge $m.blinkAt + 1) { $m.blinkAt = $m.tick + $script:Rnd.Next(25, 70) }
    }

    $geo = Get-MascotGeo $f
    if (-not [object]::ReferenceEquals($geo, $m.key)) {
        $m.key = $geo
        $UI.MascotBody.Data = $geo.body
        $UI.MascotEyes.Data = $geo.eyes
        $UI.MascotFx.Data   = $geo.fx
        $UI.MascotSand.Data = $geo.sand
        for ($i = 0; $i -lt $script:SkinPaths.Count; $i++) { $script:SkinPaths[$i].Data = $geo.acc[$i] }
    }
    # Claude Code animations run at its pace - 60 ms per frame, everything else 90 ms.
    $ms = $(if ($m.act -and $ClawdSeqs.Contains($m.act)) { $ClawdFrameMs } else { 90 })
    if ($mascotTimer.Interval.TotalMilliseconds -ne $ms) { $mascotTimer.Interval = [TimeSpan]::FromMilliseconds($ms) }
    # Barely alive - sways.
    $rx = $m.x
    if ($tier.stagger -and $mood -notin @('sleep', 'dead')) { $rx += 1.5 * [math]::Sin($m.tick / 3.0) }
    [System.Windows.Controls.Canvas]::SetLeft($UI.Mascot, [math]::Round($rx))
    [System.Windows.Controls.Canvas]::SetBottom($UI.Mascot, $f.lift - $MascotSink)

    # Sleep: a "z" floats up from behind the head and fades.
    if ($zzz) {
        $p = ($m.tick % 30) / 30.0
        $z = $UI.MascotZ
        $z.Visibility = 'Visible'
        $z.FontSize   = 7 + 4 * $p
        $z.Opacity    = 1 - $p
        $zb = $(if ($f.dig -gt 0) { 9 } elseif ($f.off -gt 0) { 12 } else { 19 })
        [System.Windows.Controls.Canvas]::SetLeft($z, $m.x + 28 + 3 * [math]::Sin($p * 2 * [math]::PI))
        [System.Windows.Controls.Canvas]::SetBottom($z, $zb + 14 * $p)
    } else {
        $UI.MascotZ.Visibility = 'Collapsed'
    }

    # Bubble over the head: "?" - a session awaits a reply, "!" - celebration.
    if ($bubble) {
        $b = $UI.MascotBubble
        $b.Visibility = 'Visible'
        if ($b.Text -ne $bubble) {
            $b.Text       = $bubble
            $b.Foreground = New-Brush $(switch ($bubble) {
                '?'     { $Palette.warn.Wpf }
                '!'     { $Palette.ok.Wpf }
                default { '#FF93C5FD' }
            })
        }
        [System.Windows.Controls.Canvas]::SetLeft($b, $m.x + $MascotW / 2 - 6)
        [System.Windows.Controls.Canvas]::SetBottom($b, 22 + $f.lift + 1.5 * [math]::Sin($m.tick / 3.0))
    } else {
        $UI.MascotBubble.Visibility = 'Collapsed'
    }

    # Session limit almost used up - sweats.
    if (($m.crit -or $m.forceCrit -or $tier.sweat) -and $mood -notin @('sleep', 'dead')) {
        $p = ($m.tick % 20) / 20.0
        $s = $UI.MascotSweat
        $s.Visibility = 'Visible'
        $s.Opacity    = 1 - $p
        [System.Windows.Controls.Canvas]::SetLeft($s, $(if ($f.look -lt 0) { 31 } else { 2 }))
        [System.Windows.Controls.Canvas]::SetTop($s, -2 + 6 * $p - $f.lift)
    } else {
        $UI.MascotSweat.Visibility = 'Collapsed'
    }

    Step-Hearts

    # Dust from under the feet while running.
    for ($i = 0; $i -lt $script:Dust.Count; $i++) {
        $r = $script:Dust[$i]
        if (-not $dust) { $r.Visibility = 'Collapsed'; continue }
        $p  = (($m.tick + $i * 3) % 9) / 9.0
        $dx = $(if ($m.dir -gt 0) { 4 - 8 * $p - 2 * $i } else { $MascotW - 6 + 8 * $p + 2 * $i })
        $r.Visibility = 'Visible'
        $r.Opacity    = 0.7 * (1 - $p)
        [System.Windows.Controls.Canvas]::SetLeft($r, $m.x + $dx)
        [System.Windows.Controls.Canvas]::SetBottom($r, 4 * $p)
    }

    # Confetti: falls, drifts sideways and shimmers as it flips.
    if ($m.confT -ge 0) {
        $i = 0
        foreach ($c in $script:Confetti) {
            $c.y -= $c.v; $c.x += $c.d
            $c.r.Visibility = $(if ($c.y -gt 0) { 'Visible' } else { 'Collapsed' })
            $c.r.Width = $(if ([math]::Floor(($m.tick + $i) / 2) % 2) { 2.5 } else { 1.2 })
            [System.Windows.Controls.Canvas]::SetLeft($c.r, $c.x)
            [System.Windows.Controls.Canvas]::SetBottom($c.r, $c.y)
            $i++
        }
        $m.confT++
        if ($m.confT -ge 45) {
            $m.confT = -1
            foreach ($c in $script:Confetti) { $c.r.Visibility = 'Collapsed' }
        }
    }

    # Petted (click) - a heart floats up.
    if ($m.loveT -ge 0) {
        $k = $m.loveT / 20.0
        $l = $UI.MascotLove
        $l.Visibility = 'Visible'
        $l.Opacity    = 1 - $k
        [System.Windows.Controls.Canvas]::SetLeft($l, $m.x + $MascotW / 2 - 5 + 2 * [math]::Sin($k * 6))
        [System.Windows.Controls.Canvas]::SetBottom($l, 23 + $f.lift + 14 * $k)
        $m.loveT++
        if ($m.loveT -ge 20) { $m.loveT = -1 }
    } else {
        $UI.MascotLove.Visibility = 'Collapsed'
    }

    # A spirit leaves the mouth of the lying Clawd and shimmers.
    if ($f.soul -gt 0.5) {
        $s = $UI.MascotSoul
        $s.Visibility = 'Visible'
        $s.Data       = Get-SoulGeo $f.soul $f.soulT
        $s.Opacity    = 0.7 + 0.15 * [math]::Sin($f.soulT / 1.7)
        [System.Windows.Controls.Canvas]::SetLeft($s, $m.x + 9.5 * $MascotPx)
        [System.Windows.Controls.Canvas]::SetTop($s, $UI.MascotArea.ActualHeight - ($f.lift + 6 * $MascotPy))
    } else {
        $UI.MascotSoul.Visibility = 'Collapsed'
    }

    # Developer mode caption: what is being shown now.
    $tag = ''
    if ($m.demo -ge 0 -or $m.force -or $m.forceCrit -or $null -ne $m.forceHearts) {
        if ($m.drainT -ge 0) { $tag = $(if ($mood -eq 'dead') { T 'mood.dead' } else { T "health.$tierN" }) }
        elseif ($m.act)      { $tag = T "act.$($m.act)" }
        elseif ($m.forceCrit) { $tag = T 'tag.sweat' }
        else                 { $tag = T "mood.$mood" }
        # Hearts set manually - show the health level too.
        if ($null -ne $m.forceHearts -and $m.drainT -lt 0 -and $mood -ne 'dead') { $tag = "$tag · $(T "health.$tierN")" }
        if ($m.demo -ge 0)   { $tag = (T 'tag.demo') -f ($m.demo + 1), $MascotDemo.Count, $tag }
        else                 { $tag = "dev · $tag" }
    }
    if ($UI.MascotTag.Text -ne $tag) { $UI.MascotTag.Text = $tag }
}
