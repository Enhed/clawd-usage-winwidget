# ---------------------------------------------------------------- update ----

# Pick up config.json edits on the fly - handy for tweaking settings without a restart.
$script:CfgStamp = $null
try { $script:CfgStamp = (Get-Item $script:ConfigPath).LastWriteTimeUtc } catch {}

function Sync-Config {
    if (-not (Test-Path $script:ConfigPath)) { return }
    $stamp = (Get-Item $script:ConfigPath).LastWriteTimeUtc
    if ($stamp -eq $script:CfgStamp) { return }
    $script:CfgStamp = $stamp
    $fresh = Load-Config
    # Leave the window position alone: the window owns it, not the file.
    $fresh.left = $script:Cfg.left
    $fresh.top  = $script:Cfg.top
    $lang = Get-Lang
    $script:Cfg = $fresh
    if ((Get-Lang) -ne $lang) { Update-Texts }
    Set-Theme
    $timer.Interval = [TimeSpan]::FromSeconds([double]$script:Cfg.refreshSeconds)
    $win.Opacity    = [double]$script:Cfg.opacity
    $win.Topmost    = [bool]$script:Cfg.topmost
    Set-Scale ([double]$script:Cfg.scale)
}

# Texts that are not recomputed every tick: XAML captions, menus,
# cached tooltips. Called at startup and on language change.
function Update-Texts {
    $UI.BtnSettings.ToolTip = T 'set.tip'
    $UI.BtnToggle.ToolTip   = T 'ui.details'
    $UI.BtnHide.ToolTip     = T 'ui.hide'
    $UI.BtnExit.ToolTip     = T 'ui.exit'
    $UI.StatusRow.ToolTip   = T 'ui.openStatus'
    $UI.LblFable.Text       = T 'ui.fable'
    $UI.LblSessions.Text    = T 'ui.sessions'
    $UI.LblDay.Text         = T 'ui.day'
    $UI.LblWeek7.Text       = T 'ui.week7'
    $UI.LblHist.Text        = T 'ui.hist'
    $UI.LblProj.Text        = T 'ui.projects'
    $UI.LblProj.ToolTip     = T 'hist.projTip'
    $script:HistKey = $null
    foreach ($k in $TrayItems.Keys) { $TrayItems[$k].Text = T $k }
    $UI.Mascot.ContextMenu  = New-MascotMenu
    $UI.Sky.ContextMenu     = $UI.Mascot.ContextMenu
    $script:SetKey = $null
    Update-Settings
    Update-SkyTip
    $script:VerTipKey = $null
    $script:SessTip   = $null
    $script:ClawdVerKey = $null
    Update-Widget
}

function Set-Period($p, $main, $extra) {
    if ($p) {
        $main.Text  = "$(Format-Count $p.requests 'request')  ·  $(Format-Count $p.sessions 'session')"
        $extra.Text = @($p.lines | ForEach-Object { Format-StatLine $_ }) -join '  ·  '
    } else {
        $main.Text  = T 'noData'
        $extra.Text = ''
    }
}

function Update-Widget {
    Sync-Config

    Collect-UsageProbe
    # Count from the last attempt, not success: if /usage doesn't answer, don't hammer it every tick.
    if (([datetime]::Now - $script:UsageTry).TotalSeconds -ge [double]$script:Cfg.usageIntervalSeconds) {
        Start-UsageProbe
    }
    Collect-VersionProbe
    Collect-ReleaseProbe
    Collect-ClawdUpdate
    if (([datetime]::Now - $script:VerAt).TotalSeconds -ge [double]$script:Cfg.versionIntervalSeconds) {
        Start-VersionProbe
    }
    Collect-StatusProbe
    if ($script:Cfg.showStatus -and
        ([datetime]::Now - $script:StatusTry).TotalSeconds -ge [double]$script:Cfg.statusIntervalSeconds) {
        Start-StatusProbe
    }
    Collect-AuthProbe
    if ($script:Cfg.showAccount -and
        ([datetime]::Now - $script:AuthTry).TotalSeconds -ge [double]$script:Cfg.accountIntervalSeconds) {
        Start-AuthProbe
    }
    # An update started by a click has finished - re-read the versions right away.
    if ($script:UpdateProc -and $script:UpdateProc.HasExited) {
        $script:UpdateProc = $null
        $script:VerAt      = [datetime]::MinValue
        Start-VersionProbe
    }
    Collect-ChangelogProbe
    Start-ChangelogProbe
    Collect-WeatherProbe
    # Coordinates changed in the config - fetch the weather again.
    $place = "$($script:Cfg.weatherLat)|$($script:Cfg.weatherLon)"
    if ($place -ne $script:WxPlace) { $script:WxPlace = $place; $script:WxTry = [datetime]::MinValue }
    if ($script:Cfg.showMascot -and $script:Cfg.showSky -and
        ([datetime]::Now - $script:WxTry).TotalSeconds -ge [double]$script:Cfg.weatherIntervalSeconds) {
        Start-WeatherProbe
    }

    $real = $script:Usage
    # The big number, BarSession and LineReset show the main limit; LblWeek, LineWeek
    # and BarWeek the other one (mainLimit; the 5-hour session unless set to week).
    $lim  = Get-Limits $real
    $main = $lim.main
    $side = $lim.side

    # --- main limit ---------------------------------------------------------

    if ($null -eq $main.pct) {
        $UI.PctText.Text       = '--'
        $UI.PctText.Foreground = New-Brush $Palette.dead.Wpf
        $UI.BarSession.Width   = 0
        if ($script:UsageAt -eq [datetime]::MinValue) { $UI.LineReset.Text = T 'loading' }
        else                                          { $UI.LineReset.Text = T 'noData' }
        Set-TrayIcon '--' $Palette.dead.Drawing
        $notify.Text = T 'tray.noData'
    } else {
        $pct   = [int]$main.pct
        $level = Get-Level $pct
        $brush = New-Brush $Palette[$level].Wpf

        $UI.PctText.Text          = "$pct"
        $UI.PctText.Foreground    = $brush
        $UI.BarSession.Background = $brush
        $UI.BarSession.Width      = [math]::Max(0, ([math]::Min(100, $pct) / 100.0) * $BarWidth)

        $resetSpan = $null
        if ($main.reset) { $resetSpan = Format-Span $main.reset }
        if ($resetSpan)      { $UI.LineReset.Text = (T 'reset.in') -f $resetSpan }
        elseif ($main.reset) { $UI.LineReset.Text = T 'reset.closed' }
        else                 { $UI.LineReset.Text = '' }

        Set-TrayIcon "$pct" $Palette[$level].Drawing
        # NotifyIcon.Text is hard-limited to 63 characters - otherwise an exception.
        if ($script:Cfg.trayResetClock) {
            # One line per limit, the main one first, with the reset as a clock time;
            # Fable only if it fits.
            $rows = @()
            foreach ($r in @(@("tray.clock.$($main.key)", $pct, $main.reset),
                             @("tray.clock.$($side.key)", $side.pct, $side.reset),
                             @('tray.clock.fable', $real.fable, $real.fableReset))) {
                if ($null -eq $r[1]) { continue }
                $row = (T $r[0]) -f $r[1]
                if ($r[2]) { $row += (T 'tray.clock.resets') -f (Format-ResetClock $r[2]) }
                $rows += $row
            }
            $tip = $rows[0]
            for ($i = 1; $i -lt $rows.Count; $i++) {
                if (($tip + "`n" + $rows[$i]).Length -le 63) { $tip += "`n" + $rows[$i] }
            }
        } else {
            $tip = (T "tray.$($main.key)") -f $pct
            if ($resetSpan) { $tip += " · $resetSpan" }
            $tip2 = @()
            if ($null -ne $side.pct)   { $tip2 += (T "tray.$($side.key)") -f $side.pct }
            if ($null -ne $real.fable) { $tip2 += "Fable $($real.fable)%" }
            if ($tip2.Count) { $tip += "`n" + ($tip2 -join ' · ') }
        }
        if ($tip.Length -gt 63) { $tip = $tip.Substring(0, 63) }
        $notify.Text = $tip
    }

    # --- the other limit, on the small line ---------------------------------

    $UI.LblWeek.Text = T "ui.$($side.key)"
    if ($null -eq $side.pct) {
        $UI.BarWeek.Width = 0
        $UI.LineWeek.Text = T 'noData'
    } else {
        $wPct = [int]$side.pct
        $UI.BarWeek.Width = [math]::Max(0, ([math]::Min(100, $wPct) / 100.0) * $BarWidth)
        $wLine = "$wPct%"
        if ($side.reset) {
            $s = Format-Span $side.reset
            if ($s) { $wLine += "  ·  $s" }
        }
        $UI.LineWeek.Text = $wLine
    }

    # --- Fable: separate weekly limit; hidden if /usage did not report it -------

    if ($real -and $null -ne $real.fable) {
        $UI.FableRow.Visibility   = 'Visible'
        $UI.FableBarBg.Visibility = 'Visible'
        $fPct = [int]$real.fable
        $UI.BarFable.Width = [math]::Max(0, ([math]::Min(100, $fPct) / 100.0) * $BarWidth)
        $fLine = "$fPct%"
        if ($real.fableReset) {
            $s = Format-Span $real.fableReset
            if ($s) { $fLine += "  ·  $s" }
        }
        $UI.LineFable.Text = $fLine
    } else {
        $UI.FableRow.Visibility   = 'Collapsed'
        $UI.FableBarBg.Visibility = 'Collapsed'
    }

    # --- Claude Code sessions -----------------------------------------------

    $ss = @()
    if ($script:Cfg.showSessions -or $script:Cfg.showMascot -or $script:Cfg.clawdSession) { $ss = Get-Sessions }
    Update-ClawdSession $ss
    # Other machines' sessions count for the line and Clawd, but never for his own session above.
    if (@($script:Cfg.remoteSessions).Count -or $script:RemoteSess.Count) { $ss = @($ss) + (Get-RemoteSessions $ss) }
    # Clawd's own session is always there: idle it is not "something running" -
    # otherwise the mascot would never fall asleep. Talking to it does count.
    $clawdHome = Get-ClawdHome
    $ss = @($ss | Where-Object { -not ($_.name -eq (Get-ClawdSessionName) -and $_.cwd.TrimEnd('\') -eq $clawdHome -and
                                       -not $_.busy -and -not $_.waiting) })

    if ($script:Cfg.showMascot) { Set-MascotMood $ss $real }
    Set-Skin
    Set-Theme
    Sync-Mascot
    Update-Advisor
    if ($script:Cfg.showReminders) { Update-Reminders }
    Update-Tasks
    Update-Actions
    Update-RemoteFeed
    Update-Badge
    if ($advWin.IsVisible) { Update-Panel }
    Update-Settings

    if (-not $script:Cfg.showSessions) {
        $UI.SessionsPanel.Visibility = 'Collapsed'
    } else {
        $UI.SessionsPanel.Visibility = 'Visible'
        $busy = @($ss | Where-Object { $_.busy })
        $wait = @($ss | Where-Object { $_.waiting })
        if (-not $ss.Count) {
            $UI.LineSessions.Text = T 'sess.none'
        } else {
            $line = Format-Count $ss.Count 'session'
            # Someone is waiting - that matters more than "0 working", and the line stays short.
            if ($busy.Count -or -not $wait.Count) { $line += "  ·  $((T 'sess.busy') -f $busy.Count)" }
            if ($wait.Count) { $line += "  ·  $((T 'sess.wait') -f $wait.Count)" }
            $UI.LineSessions.Text = $line
        }
        $tip = ($ss | ForEach-Object {
            $mark = $(if ($_.busy) { '▶' } elseif ($_.waiting) { '?' } else { '○' })
            $what = $(if ($_.waiting -and $_.waitingFor) { " [$($_.waitingFor)]" } else { '' })
            $where = $(if ($_.host -and $_.cwd) { "$($_.host): $($_.cwd)" } elseif ($_.host) { $_.host } else { $_.cwd })
            "$mark $($_.name)$what — $where"
        }) -join "`n"
        if ($tip -ne $script:SessTip) {
            $script:SessTip = $tip
            $UI.SessionsPanel.ToolTip = $(if ($tip) { $tip } else { $null })
        }
    }

    # --- service status -----------------------------------------------------

    if (-not $script:Cfg.showStatus) {
        $UI.StatusRow.Visibility = 'Collapsed'
    } else {
        $UI.StatusRow.Visibility = 'Visible'
        $st    = $script:Status
        $stale = ([datetime]::Now - $script:StatusAt).TotalSeconds -gt (3 * [double]$script:Cfg.statusIntervalSeconds + 30)
        $extra = ''
        if (-not $st -or $stale) {
            $dot  = $Palette.dead.Wpf
            $text = $(if ($st) { T 'st.offline' } else { T 'st.loading' })
            $fg   = '#FF8B8B94'
        } elseif ($st.indicator -eq 'none' -and -not $st.broken.Count -and -not $st.incidents.Count) {
            $dot  = $Palette.ok.Wpf
            $text = T 'st.ok'
            $fg   = '#FF8B8B94'
        } else {
            $dot = $(if ($st.indicator -in @('major','critical')) { $Palette.crit.Wpf } else { $Palette.warn.Wpf })
            $fg  = '#FFD4D4D8'
            if ($st.incidents.Count) {
                $text = $st.incidents -join '  ·  '
            } elseif ($st.indicator -eq 'maintenance') {
                $text = T 'st.maint'
            } else {
                $text = T 'st.issues'
            }
            $extra = @($st.broken | ForEach-Object { "$($_.name): $(T "comp.$($_.state)" $_.state)" }) -join '  ·  '
        }
        $UI.StatusDot.Fill        = New-Brush $dot
        $UI.LineStatus.Text       = $text
        $UI.LineStatus.Foreground = New-Brush $fg
        $UI.LineStatus2.Text      = $extra
        $UI.LineStatus2.Visibility = $(if ($extra) { 'Visible' } else { 'Collapsed' })
    }

    # --- details ------------------------------------------------------------

    Set-Period $(if ($real) { $real.day })   $UI.LineDay   $UI.LineDay2
    Set-Period $(if ($real) { $real.week7 }) $UI.LineWeek7 $UI.LineWeek72
    if ($script:Cfg.showStats) { $UI.StatsPanel.Visibility = 'Visible' }
    else                       { $UI.StatsPanel.Visibility = 'Collapsed' }
    Update-History

    $hasUpdate = Test-UpdateAvailable
    # Recreate the tooltip only when its content changes: replacing ToolTip every tick
    # would close it right under the cursor.
    $tipKey = ''
    if ($hasUpdate) {
        $tipKey = "$($script:VerLocal)|$($script:VerLatest)"
        if ($script:Changes) { $tipKey += "|$($script:Changes.for)|$($script:Changes.from)" }
    }
    if ($tipKey -ne $script:VerTipKey) {
        $script:VerTipKey = $tipKey
        if ($hasUpdate) { $UI.LineVersion.ToolTip = New-ChangesTooltip }
        else            { $UI.LineVersion.ToolTip = T 'chg.open' }
    }

    if ($script:VerLocal) {
        if ($script:UpdateProc) {
            $UI.LineVersion.Text       = "v$($script:VerLocal)  ·  $(T 'ver.updating')"
            $UI.LineVersion.Foreground = New-Brush $Palette.warn.Wpf
        } elseif ($hasUpdate) {
            $UI.LineVersion.Text       = "v$($script:VerLocal)  ·  $((T 'ver.available') -f $script:VerLatest)"
            $UI.LineVersion.Foreground = New-Brush $Palette.warn.Wpf
        } elseif ($script:VerLatest) {
            $UI.LineVersion.Text       = "v$($script:VerLocal)  ·  $(T 'ver.latest')"
            $UI.LineVersion.Foreground = New-Brush '#FF8B8B94'
        } else {
            $UI.LineVersion.Text       = "v$($script:VerLocal)"
            $UI.LineVersion.Foreground = New-Brush '#FF8B8B94'
        }
    } else {
        $UI.LineVersion.Text = ''
    }

    # The widget's own version: yellow with a new release out. The tooltip is
    # recreated only when something changes - otherwise it closes under the cursor.
    $hasRel = Test-ClawdUpdate
    $relKey = "$(Get-Lang)|$hasRel|$(if ($script:ClawdRel) { $script:ClawdRel.ver })|$([bool]$script:ClawdDl)"
    if ($relKey -ne $script:ClawdVerKey) {
        $script:ClawdVerKey = $relKey
        if ($script:ClawdDl) {
            $UI.LineClawdVer.Text       = T 'clawd.updating'
            $UI.LineClawdVer.Foreground = New-Brush $Palette.warn.Wpf
        } elseif ($hasRel) {
            $UI.LineClawdVer.Text       = (T 'clawd.available') -f $script:ClawdRel.ver
            $UI.LineClawdVer.Foreground = New-Brush $Palette.warn.Wpf
            $UI.LineClawdVer.ToolTip    = New-ClawdUpdateTooltip
        } else {
            $UI.LineClawdVer.Text       = "Clawd v$WidgetVersion"
            $UI.LineClawdVer.Foreground = New-Brush '#FF6B7280'
            $UI.LineClawdVer.ToolTip    = New-ClawdChangesTooltip
        }
    }

    # Time of the last /usage reply; if it hasn't come for a while - say so honestly.
    if ($script:UsageAt -eq [datetime]::MinValue) {
        $UI.LineStamp.Text = ''
    } else {
        $stamp = $script:UsageAt.ToString('HH:mm:ss')
        $stale = ([datetime]::Now - $script:UsageAt).TotalSeconds -gt (3 * [double]$script:Cfg.usageIntervalSeconds + 30)
        if ($stale) { $stamp = "$(T 'stale') · $stamp" }
        $UI.LineStamp.Text = $stamp
    }

    # --- account ------------------------------------------------------------

    $acc = $script:Account
    if (-not $script:Cfg.showAccount -or -not $acc) {
        $UI.LineAccount.Text = ''
    } elseif (-not $acc.loggedIn) {
        $UI.LineAccount.Text       = T 'acc.out'
        $UI.LineAccount.Foreground = New-Brush $Palette.crit.Wpf
    } else {
        $UI.LineAccount.Text       = (@($acc.plan, $acc.email) | Where-Object { $_ }) -join '  ·  '
        $UI.LineAccount.Foreground = New-Brush '#FF52525B'
        $UI.LineAccount.ToolTip    = $UI.LineAccount.Text
    }
}
