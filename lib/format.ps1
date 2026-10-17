# ------------------------------------------------------------ formatters ----

function Format-Span([datetime]$endUtc) {
    $span = $endUtc.ToUniversalTime() - [datetime]::UtcNow
    if ($span.TotalSeconds -le 0) { return $null }
    if ($span.TotalHours -ge 24) { return ((T 'span.d') -f $span.Days, $span.Hours) }
    # [int] in PowerShell rounds rather than truncates - Floor is what we need here.
    if ($span.TotalHours -ge 1)  { return ((T 'span.h') -f [math]::Floor($span.TotalHours), $span.Minutes) }
    return ((T 'span.m') -f $span.Minutes)
}

# Reset as a clock time: "03:20" today, "tmrw 01:00" tomorrow, "Sun 01:49" further off.
function Format-ResetClock([datetime]$at) {
    $at = $at.ToLocalTime()
    $hm = $at.ToString('HH:mm')
    $days = ($at.Date - (Get-Date).Date).Days
    if ($days -le 0) { return $hm }
    if ($days -eq 1) { return ((T 'clock.tmrw') -f $hm) }
    return $at.ToString('ddd ', (Get-LangCulture)) + $hm
}

function Get-Level([double]$pct) {
    if ($pct -ge $script:Cfg.critPercent) { return 'crit' }
    if ($pct -ge $script:Cfg.warnPercent) { return 'warn' }
    return 'ok'
}

$Palette = @{
    ok   = @{ Wpf = '#FF4ADE80'; Drawing = [System.Drawing.Color]::FromArgb(74,222,128) }
    warn = @{ Wpf = '#FFFBBF24'; Drawing = [System.Drawing.Color]::FromArgb(251,191,36) }
    crit = @{ Wpf = '#FFF87171'; Drawing = [System.Drawing.Color]::FromArgb(248,113,113) }
    dead = @{ Wpf = '#FF6B7280'; Drawing = [System.Drawing.Color]::FromArgb(107,114,128) }
}

function New-Brush([string]$hex) {
    # A theme colour is the theme's shared brush, recoloured in place (theme.ps1).
    if ($script:ThemeBrush) { $b = $script:ThemeBrush[$hex.ToUpper()]; if ($b) { return $b } }
    return New-Object System.Windows.Media.SolidColorBrush(
        [System.Windows.Media.ColorConverter]::ConvertFromString($hex))
}
