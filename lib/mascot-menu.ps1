# Right-click on the mascot: developer mode. State holds until "Auto" is chosen.
function New-MascotMenu {
    $cm = New-Object System.Windows.Controls.ContextMenu
    $items = @{ moods = @() }

    $head = New-Object System.Windows.Controls.MenuItem
    $head.Header = T 'mm.head'
    $head.IsEnabled = $false
    $cm.Items.Add($head) | Out-Null
    $cm.Items.Add((New-Object System.Windows.Controls.Separator)) | Out-Null

    $auto = New-Object System.Windows.Controls.MenuItem
    $auto.Header = T 'mm.auto'
    $auto.add_Click({
        Stop-MascotDemo
        $script:Mz.forceHearts = $null
        $script:Sky.force = $null; $script:Sky.forceWx = $null; $script:Sky.key = ''
        Update-SkyTip
    })
    $cm.Items.Add($auto) | Out-Null
    $items.auto = $auto

    $states = New-Object System.Windows.Controls.MenuItem
    $states.Header = T 'mm.state'
    foreach ($id in $MascotMoods) {
        $mi = New-Object System.Windows.Controls.MenuItem
        $mi.Header = T "mood.$id"
        $mi.Tag    = $id
        $mi.add_Click({
            param($s, $e)
            Stop-MascotDemo
            $script:Mz.force = $s.Tag
        })
        $states.Items.Add($mi) | Out-Null
        $items.moods += $mi
    }
    $cm.Items.Add($states) | Out-Null

    $acts = New-Object System.Windows.Controls.MenuItem
    $acts.Header = T 'mm.anim'
    foreach ($id in $MascotActs.Keys) {
        $mi = New-Object System.Windows.Controls.MenuItem
        $mi.Header = T "act.$id"
        $mi.Tag    = $id
        $mi.add_Click({
            param($s, $e)
            Start-MascotAct $s.Tag
        })
        $acts.Items.Add($mi) | Out-Null
    }
    $cm.Items.Add($acts) | Out-Null

    $crit = New-Object System.Windows.Controls.MenuItem
    $crit.Header      = T 'mm.sweat'
    $crit.IsCheckable = $true
    $crit.add_Click({
        param($s, $e)
        $script:Mz.forceCrit = $s.IsChecked
    })
    $cm.Items.Add($crit) | Out-Null
    $items.crit = $crit

    # Hearts: -1 - from the real limit, otherwise the number of halves 0..6.
    $hearts = New-Object System.Windows.Controls.MenuItem
    $hearts.Header = T 'mm.hearts'
    $items.hearts = @()
    $heartNames = @(@(-1, (T 'mm.byLimit')), @(6, '3'), @(5, '2½'), @(4, '2'), @(3, '1½'),
                    @(2, '1'), @(1, '½'), @(0, '0'))
    foreach ($hn in $heartNames) {
        $mi = New-Object System.Windows.Controls.MenuItem
        $mi.Header = $hn[1]
        $mi.Tag    = [int]$hn[0]
        $mi.add_Click({
            param($s, $e)
            if ($script:Mz.drainT -ge 0) { Stop-MascotDemo }
            $script:Mz.forceHearts = $(if ($s.Tag -lt 0) { $null } else { $s.Tag })
        })
        $hearts.Items.Add($mi) | Out-Null
        $items.hearts += $mi
    }
    $hearts.Items.Add((New-Object System.Windows.Controls.Separator)) | Out-Null
    $drain = New-Object System.Windows.Controls.MenuItem
    $drain.Header = T 'mm.drain'
    $drain.add_Click({
        Stop-MascotDemo
        $script:Mz.drainT = 0
    })
    $hearts.Items.Add($drain) | Out-Null
    $cm.Items.Add($hearts) | Out-Null

    # Sky: time of day and weather set manually.
    $sky = New-Object System.Windows.Controls.MenuItem
    $sky.Header = T 'mm.sky'
    $items.phases = @(); $items.wx = @()
    foreach ($ph in @(, @('', (T 'mm.byClock'))) + @($SkyPhases | ForEach-Object { , @($_, (T "phase.$_")) })) {
        $mi = New-Object System.Windows.Controls.MenuItem
        $mi.Header = $ph[1]
        $mi.Tag    = $ph[0]
        $mi.add_Click({
            param($s, $e)
            $script:Sky.force = $(if ($s.Tag) { $s.Tag } else { $null })
            $script:Sky.key = ''
            Update-SkyTip
        })
        $sky.Items.Add($mi) | Out-Null
        $items.phases += $mi
    }
    $sky.Items.Add((New-Object System.Windows.Controls.Separator)) | Out-Null
    foreach ($wc in @(-1, 0, 2, 3, 45, 53, 63, 82, 95, 73)) {
        $mi = New-Object System.Windows.Controls.MenuItem
        $mi.Header = $(if ($wc -lt 0) { T 'mm.wxLive' } else { (Get-WeatherKind $wc).name })
        $mi.Tag    = [int]$wc
        $mi.add_Click({
            param($s, $e)
            $script:Sky.forceWx = $(if ($s.Tag -lt 0) { $null } else { $s.Tag })
            $script:Sky.key = ''
            Update-SkyTip
        })
        $sky.Items.Add($mi) | Out-Null
        $items.wx += $mi
    }
    $cm.Items.Add($sky) | Out-Null
    $items.sky = $sky

    $cm.Items.Add((New-Object System.Windows.Controls.Separator)) | Out-Null
    $demo = New-Object System.Windows.Controls.MenuItem
    $demo.Header = T 'mm.demo'
    $demo.add_Click({
        Stop-MascotDemo
        $script:Mz.demo = 0
    })
    $cm.Items.Add($demo) | Out-Null
    $items.demo = $demo

    $script:MascotMenu = $items
    $cm.add_Opened({
        $m = $script:Mz
        $i = $script:MascotMenu
        $i.auto.IsChecked = (-not $m.force -and -not $m.forceCrit -and $m.demo -lt 0 -and
                             $null -eq $m.forceHearts)
        foreach ($mi in $i.moods) { $mi.IsChecked = ($m.demo -lt 0 -and $m.force -eq $mi.Tag) }
        $fh = $(if ($null -eq $m.forceHearts -or $m.drainT -ge 0) { -1 } else { [int]$m.forceHearts })
        foreach ($mi in $i.hearts) { $mi.IsChecked = ($mi.Tag -eq $fh) }
        $i.crit.IsChecked = $m.forceCrit
        $i.sky.IsEnabled = ($UI.Sky.Visibility -eq 'Visible')
        foreach ($mi in $i.phases) { $mi.IsChecked = ("$($script:Sky.force)" -eq $mi.Tag) }
        $fw = $(if ($null -eq $script:Sky.forceWx) { -1 } else { [int]$script:Sky.forceWx })
        foreach ($mi in $i.wx) { $mi.IsChecked = ($mi.Tag -eq $fw) }
        $i.demo.IsChecked = ($m.demo -ge 0)
    })
    return $cm
}
$UI.Mascot.ContextMenu = New-MascotMenu
$UI.Sky.ContextMenu    = $UI.Mascot.ContextMenu
Update-SkyTip

# Animation runs only while the window is visible - no CPU spent in the tray.
$mascotTimer = New-Object System.Windows.Threading.DispatcherTimer
$mascotTimer.Interval = [TimeSpan]::FromMilliseconds(90)
$mascotTimer.add_Tick({
    try { Step-Mascot } catch {
        $mascotTimer.Stop()
        $script:Mz.broken = $true
        try {
            "$(Get-Date -Format s)`tmascot: $($_.Exception.Message)`t$($_.InvocationInfo.PositionMessage)" |
                Out-File (Join-Path $script:Root 'widget-error.log') -Append -Encoding utf8
        } catch {}
    }
    if ($script:Space.on) {
        try { Step-Space } catch {
            $script:Space.broken = $true
            Sync-Space
            try {
                "$(Get-Date -Format s)`tspace: $($_.Exception.Message)`t$($_.InvocationInfo.PositionMessage)" |
                    Out-File (Join-Path $script:Root 'widget-error.log') -Append -Encoding utf8
            } catch {}
        }
        return
    }
    if ($UI.Sky.Visibility -ne 'Visible' -or $script:Sky.broken) { return }
    try { Step-Sky } catch {
        $script:Sky.broken = $true
        $UI.Sky.Visibility = 'Collapsed'
        try {
            "$(Get-Date -Format s)`tsky: $($_.Exception.Message)`t$($_.InvocationInfo.PositionMessage)" |
                Out-File (Join-Path $script:Root 'widget-error.log') -Append -Encoding utf8
        } catch {}
    }
})

function Sync-Mascot {
    $show = [bool]$script:Cfg.showMascot
    $UI.MascotArea.Visibility = $(if ($show) { 'Visible' } else { 'Collapsed' })
    if (-not $show) { $UI.Hearts.Visibility = 'Collapsed'; $script:Mz.halves = $null }
    $sky = $show -and [bool]$script:Cfg.showSky -and -not $script:Sky.broken
    $UI.Sky.Visibility = $(if ($sky) { 'Visible' } else { 'Collapsed' })
    $run = $show -and $win.IsVisible -and -not $script:Mz.broken
    if ($run -and -not $mascotTimer.IsEnabled)     { $mascotTimer.Start() }
    elseif (-not $run -and $mascotTimer.IsEnabled) { $mascotTimer.Stop() }
}
$win.add_IsVisibleChanged({ Sync-Mascot })
