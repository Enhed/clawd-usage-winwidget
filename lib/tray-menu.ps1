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

$miBigger = $menu.Items.Add('')
$TrayItems['menu.bigger'] = $miBigger
$miBigger.add_Click({
    $script:Cfg.scale = [math]::Round([double]$script:Cfg.scale + 0.1, 2)
    Set-Scale ([double]$script:Cfg.scale)
    Save-Config $script:Cfg
})

$miSmaller = $menu.Items.Add('')
$TrayItems['menu.smaller'] = $miSmaller
$miSmaller.add_Click({
    $script:Cfg.scale = [math]::Round([double]$script:Cfg.scale - 0.1, 2)
    Set-Scale ([double]$script:Cfg.scale)
    Save-Config $script:Cfg
})

$miAdvisor = $menu.Items.Add('')
$TrayItems['menu.advisor'] = $miAdvisor
$miAdvisor.add_Click({
    Start-AdvisorScan
    if (-not $advWin.IsVisible) { Show-Panel }
    Update-PanelBusy
})

$miConfig = $menu.Items.Add('')
$TrayItems['menu.config'] = $miConfig
$miConfig.add_Click({
    if (-not (Test-Path $script:ConfigPath)) { Save-Config $script:Cfg }
    Start-Process notepad.exe $script:ConfigPath
})

# Language: language names are written in themselves, the current one is checked.
$miLang = New-Object System.Windows.Forms.ToolStripMenuItem
$menu.Items.Add($miLang) | Out-Null
$TrayItems['menu.language'] = $miLang
foreach ($code in $Languages.Keys) {
    $mi = $miLang.DropDownItems.Add($Languages[$code])
    $mi.Tag = $code
    $mi.add_Click({
        param($s, $e)
        $script:Cfg.language = $s.Tag
        Save-Config $script:Cfg
        Update-Texts
    })
}
$miLang.add_DropDownOpening({
    foreach ($mi in $miLang.DropDownItems) { $mi.Checked = ($mi.Tag -eq (Get-Lang)) }
})

# Clawd's own session with Remote Control; the folder and flags are in config.json.
$miClawdSession = $menu.Items.Add('')
$TrayItems['menu.clawdSession'] = $miClawdSession
$miClawdSession.add_Click({
    $script:Cfg.clawdSession = -not [bool]$script:Cfg.clawdSession
    Save-Config $script:Cfg
})
$miClawdRestart = $menu.Items.Add('')
$TrayItems['menu.clawdRestart'] = $miClawdRestart
$miClawdRestart.add_Click({ Restart-ClawdSession })
$menu.add_Opening({
    $miClawdSession.Checked = [bool]$script:Cfg.clawdSession
    $miClawdRestart.Visible = [bool]$script:Cfg.clawdSession
})

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
