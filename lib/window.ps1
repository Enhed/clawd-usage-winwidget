# ------------------------------------------------------------------ XAML ----

# The window markup lives next door in widget.xaml.
$xamlText = Get-Content -Raw -Encoding UTF8 (Join-Path $script:Root 'widget.xaml')

[xml]$xaml = $xamlText
$reader = New-Object System.Xml.XmlNodeReader $xaml
$win    = [Windows.Markup.XamlReader]::Load($reader)

$UI = @{}
foreach ($n in @('BtnToggle','BtnHide','BtnExit','PctText','PctSign','BarSession',
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
if ($null -ne $script:Cfg.left -and $null -ne $script:Cfg.top) {
    $win.Left = [double]$script:Cfg.left
    $win.Top  = [double]$script:Cfg.top
} else {
    $area = [System.Windows.SystemParameters]::WorkArea   # in DIP, like the window Left/Top
    $win.Left = $area.Right - 282
    $win.Top  = $area.Top + 20
}
