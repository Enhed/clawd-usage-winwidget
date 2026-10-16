# ------------------------------------------------------------------ tray ----

$notify = New-Object System.Windows.Forms.NotifyIcon
$notify.Text    = 'clawd-usage-winwidget'
$notify.Visible = $true

$script:LastIconHandle = [IntPtr]::Zero

function Set-TrayIcon([string]$text, [System.Drawing.Color]$color) {
    $bmp = New-Object System.Drawing.Bitmap 32,32
    $g   = [System.Drawing.Graphics]::FromImage($bmp)
    try {
        $g.SmoothingMode     = 'AntiAlias'
        $g.TextRenderingHint = 'ClearTypeGridFit'
        $g.Clear([System.Drawing.Color]::Transparent)
        $brush = New-Object System.Drawing.SolidBrush $color
        $g.FillEllipse($brush, 0, 0, 31, 31)
        $brush.Dispose()

        if ($text.Length -ge 3) { $size = 14 } else { $size = 17 }
        $font = New-Object System.Drawing.Font 'Segoe UI', $size, ([System.Drawing.FontStyle]::Bold), ([System.Drawing.GraphicsUnit]::Pixel)
        $fmt  = New-Object System.Drawing.StringFormat
        $fmt.Alignment     = 'Center'
        $fmt.LineAlignment = 'Center'
        $rect = New-Object System.Drawing.RectangleF 0,0,32,32
        $g.DrawString($text, $font, [System.Drawing.Brushes]::Black, $rect, $fmt)
        $font.Dispose(); $fmt.Dispose()
    } finally {
        $g.Dispose()
    }

    $h = $bmp.GetHicon()
    $notify.Icon = [System.Drawing.Icon]::FromHandle($h)
    if ($script:LastIconHandle -ne [IntPtr]::Zero) {
        [Win32.IconUtil]::DestroyIcon($script:LastIconHandle) | Out-Null
    }
    $script:LastIconHandle = $h
    $bmp.Dispose()
}

function Stop-Widget {
    try {
        $script:Cfg.left = [math]::Round($win.Left)
        $script:Cfg.top  = [math]::Round($win.Top)
        Save-Config $script:Cfg
    } catch {}
    try { Remove-Item $script:UsageFile -ErrorAction Stop } catch {}
    try { Remove-Item $script:AuthFile -ErrorAction Stop } catch {}
    $notify.Visible = $false
    $notify.Dispose()
    if ($script:LastIconHandle -ne [IntPtr]::Zero) {
        [Win32.IconUtil]::DestroyIcon($script:LastIconHandle) | Out-Null
    }
    $win.Close()
    [System.Windows.Threading.Dispatcher]::CurrentDispatcher.InvokeShutdown()
}
