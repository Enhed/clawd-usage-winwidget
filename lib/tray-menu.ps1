# -------------------------------------------------------------- tray menu ----

$menu = New-Object System.Windows.Forms.ContextMenuStrip

# Item captions are set by Update-Texts using the keys from $TrayItems.
$TrayItems = [ordered]@{}

# The widget's name and version on top, not clickable.
$miVersion = $menu.Items.Add("clawd-usage-winwidget v$WidgetVersion")
$miVersion.Enabled = $false
$menu.Items.Add((New-Object System.Windows.Forms.ToolStripSeparator)) | Out-Null

$miToggle = $menu.Items.Add('')
$TrayItems['menu.toggle'] = $miToggle
$miToggle.add_Click({
    if ($win.IsVisible) { $win.Hide() } else { $win.Show(); $win.Activate() }
})

$miRefresh = $menu.Items.Add('')
$TrayItems['menu.refresh'] = $miRefresh
$miRefresh.add_Click({
    Start-UsageProbe
    $kick.Start()
})

# Everything else - language, theme, skins, what the window shows - is in the
# settings window (settings.ps1).
$miSettings = $menu.Items.Add('')
$TrayItems['menu.settings'] = $miSettings
$miSettings.add_Click({ Show-Settings })

$menu.Items.Add((New-Object System.Windows.Forms.ToolStripSeparator)) | Out-Null

$miExit = $menu.Items.Add('')
$TrayItems['menu.exit'] = $miExit
$miExit.add_Click({ Stop-Widget })

$notify.ContextMenuStrip = $menu
$notify.add_MouseClick({
    param($s, $e)
    if ($e.Button -eq [System.Windows.Forms.MouseButtons]::Left) {
        if ($win.IsVisible) { $win.Hide() } else { $win.Show(); $win.Activate() }
    }
})
