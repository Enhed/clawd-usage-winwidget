# ------------------------------------------------------------------ XAML ----

# The window markup lives next door in widget.xaml.
$xamlText = Convert-ThemeXaml (Get-Content -Raw -Encoding UTF8 (Join-Path $script:Root 'widget.xaml'))

[xml]$xaml = $xamlText
$reader = New-Object System.Xml.XmlNodeReader $xaml
$win    = [Windows.Markup.XamlReader]::Load($reader)
Add-ThemeTo $win -Pattern

$UI = @{}
foreach ($n in @('BtnSettings','BtnToggle','BtnHide','BtnExit','PctText','PctSign','BarSession',
                 'LineReset','LineWeek','BarWeek','LineStamp',
                 'Details','LineDay','LineDay2','LineWeek7','LineWeek72','LineVersion','LineClawdVer',
                 'FableRow','FableBarBg','LineFable','BarFable',
                 'StatusRow','StatusDot','LineStatus','LineStatus2','StatsPanel',
                 'SessionsPanel','LineSessions','LineAccount',
                 'MascotArea','Mascot','MascotBody','MascotEyes','MascotFx','MascotSand','MascotSweat','MascotZ',
                 'MascotBubble','MascotTag','Hearts','MascotLove','MascotSoul','Sky','SkyFx',
                 'LblWeek','LblFable','LblSessions','LblDay','LblWeek7',
                 'TipBadge','TipIcon','TipCount',
                 'HistPanel','LblHist','HistChart','HistDays','HistCaption','ProjPanel','LblProj','ProjRows')) {
    $UI[$n] = $win.FindName($n)
}

$win.Opacity = [double]$script:Cfg.opacity
$win.Topmost = [bool]$script:Cfg.topmost
$BarWidth    = 238.0

# Scale is set by a transform on the root Border: LayoutTransform affects measuring,
# so SizeToContent grows the window by itself, and all layout stays in original
# units - no need to recompute bar widths.
function Set-Scale([double]$k) {
    if ($k -lt 0.6) { $k = 0.6 }
    if ($k -gt 4.0) { $k = 4.0 }
    $win.Content.LayoutTransform = New-Object System.Windows.Media.ScaleTransform $k, $k
}
Set-Scale ([double]$script:Cfg.scale)

$win.WindowStartupLocation = 'Manual'
# Keep enough of the scaled header on a monitor to let the user drag the window.
# The virtual screen's bounding rectangle also covers gaps between monitors.
function Test-SavedPlace([double]$left, [double]$top, [double]$width, [double]$scale,
                         [System.Windows.Rect[]]$workAreas) {
    $headerTop = $top + 11 * $scale
    $headerBottom = $top + 30 * $scale
    foreach ($area in $workAreas) {
        $visibleWidth = [math]::Min($left + $width, $area.Right) - [math]::Max($left, $area.Left)
        $visibleHeight = [math]::Min($headerBottom, $area.Bottom) - [math]::Max($headerTop, $area.Top)
        if ($visibleWidth -ge 60 -and $visibleHeight -ge (12 * $scale)) { return $true }
    }
    return $false
}

$windowScale = $win.Content.LayoutTransform.ScaleX
$windowWidth = $win.Content.Width * $windowScale
$area = [System.Windows.SystemParameters]::WorkArea
$win.Left = [math]::Max($area.Left, $area.Right - $windowWidth - 20)
$win.Top = $area.Top + 20

if ($null -ne $script:Cfg.left -and $null -ne $script:Cfg.top) {
    # PowerShell hosts the widget with system DPI awareness. Convert the WinForms
    # screen rectangles to the same device-independent units as WPF Left/Top.
    $dpi = [System.Windows.Media.VisualTreeHelper]::GetDpi($win)
    $workAreas = foreach ($screen in [System.Windows.Forms.Screen]::AllScreens) {
        $bounds = $screen.WorkingArea
        [System.Windows.Rect]::new(
            $bounds.Left / $dpi.DpiScaleX, $bounds.Top / $dpi.DpiScaleY,
            $bounds.Width / $dpi.DpiScaleX, $bounds.Height / $dpi.DpiScaleY)
    }
    $left = [double]$script:Cfg.left
    $top = [double]$script:Cfg.top
    if (Test-SavedPlace $left $top $windowWidth $windowScale $workAreas) {
        $win.Left = $left
        $win.Top = $top
    }
}
