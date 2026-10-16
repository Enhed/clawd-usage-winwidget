# ---------------------------------------------------------------- events ----

$border = $win.Content
$border.add_MouseLeftButtonDown({
    try {
        $win.DragMove()
        # Save the position right after dragging: if the process is killed hard,
        # the coordinates are still not lost.
        $script:Cfg.left = [math]::Round($win.Left)
        $script:Cfg.top  = [math]::Round($win.Top)
        Save-Config $script:Cfg
    } catch {}
})
function Set-Details([bool]$open) {
    if ($open) {
        $UI.Details.Visibility = 'Visible'
        $UI.BtnToggle.Text     = [char]0x25B4
    } else {
        $UI.Details.Visibility = 'Collapsed'
        $UI.BtnToggle.Text     = [char]0x25BE
    }
    $script:Cfg.expanded = $open
    Save-Config $script:Cfg
}

$UI.BtnToggle.add_MouseLeftButtonDown({
    param($s, $e)
    $e.Handled = $true
    Set-Details ($UI.Details.Visibility -ne 'Visible')
})
$UI.BtnHide.add_MouseLeftButtonDown({
    param($s, $e)
    $e.Handled = $true
    $win.Hide()
})
$UI.LineVersion.add_MouseLeftButtonDown({
    param($s, $e)
    if (-not (Test-UpdateAvailable)) { return }
    $e.Handled = $true
    Start-ClaudeUpdate
    Update-Widget
})
$UI.Mascot.add_MouseLeftButtonDown({
    param($s, $e)
    $e.Handled = $true
    $script:Mz.idleSince = Get-Date
    Start-MascotClick
})
$UI.StatusRow.add_MouseLeftButtonDown({
    param($s, $e)
    $e.Handled = $true
    Start-Process $StatusUrl
})
$UI.BtnExit.add_MouseLeftButtonDown({
    param($s, $e)
    $e.Handled = $true
    Stop-Widget
})

$timer = New-Object System.Windows.Threading.DispatcherTimer
$timer.Interval = [TimeSpan]::FromSeconds([double]$script:Cfg.refreshSeconds)
$timer.add_Tick({
    try { Update-Widget } catch {
        $UI.LineStamp.Text = T 'error'
        try {
            "$(Get-Date -Format s)`t$($_.Exception.Message)`t$($_.InvocationInfo.PositionMessage)" |
                Out-File (Join-Path $script:Root 'widget-error.log') -Append -Encoding utf8
        } catch {}
    }
})
$timer.Start()

# The /usage reply arrives in a couple of seconds - after start and a manual refresh
# pick it up before the full tick.
$kick = New-Object System.Windows.Threading.DispatcherTimer
$kick.Interval = [TimeSpan]::FromSeconds(1)
$kick.add_Tick({
    Collect-UsageProbe
    if (-not $script:UsageProc) {
        $kick.Stop()
        try { Update-Widget } catch {}
    }
})
