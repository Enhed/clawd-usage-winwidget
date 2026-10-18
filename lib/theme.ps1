# ----------------------------------------------------------------- theme ----
# Colour themes. The markup and the modules are written in the classic colours;
# each of the colours below is one shared brush, and a theme recolours these brushes
# in place - so everything painted with them changes at once, without rebuilding.
# The XAML gets them as {DynamicResource} (Convert-ThemeXaml), the code through
# New-Brush. Level colours (green/yellow/red), the sky and Clawd are not themed.
# A theme may also have a pattern: small pixel pictures repeated faintly over the
# window's background, like a chat wallpaper.

$ThemeBase = [ordered]@{
    bg      = '#FF1A1A1E'   # window
    code    = '#FF141416'   # code blocks, fields
    card    = '#FF26262C'   # cards in the panel
    card2   = '#FF2B3245'   # a highlighted card
    textHi  = '#FFF4F4F5'
    text    = '#FFE4E4E7'
    text2   = '#FFD4D4D8'
    text3   = '#FFB4B4BC'
    text4   = '#FFA1A1AA'
    muted   = '#FF8B8B94'   # captions
    dim     = '#FF6B7280'   # hints
    faint   = '#FF52525B'
    off     = '#FF3F3F46'   # an empty heart
    accent  = '#FF60A5FA'   # links, the weekly bar
    accent2 = '#FF93C5FD'
}

# Names - T "theme.<id>". Only what differs from classic.
$Themes = [ordered]@{
    classic  = @{}
    oled     = @{ bg = '#FF000000'; code = '#FF0A0A0A'; card = '#FF141414'; card2 = '#FF1A2133' }
    midnight = @{ bg = '#FF0F172A'; code = '#FF0B1222'; card = '#FF1E293B'; card2 = '#FF27354F'
                  textHi = '#FFF1F5F9'; text = '#FFE2E8F0'; text2 = '#FFCBD5E1'; text3 = '#FFA9B6C8'; text4 = '#FF94A3B8'
                  muted = '#FF8494AB'; dim = '#FF64748B'; faint = '#FF475569'; off = '#FF334155'
                  accent = '#FF38BDF8'; accent2 = '#FF7DD3FC' }
    mocha    = @{ bg = '#FF1E1E2E'; code = '#FF181825'; card = '#FF313244'; card2 = '#FF3B3F5C'
                  textHi = '#FFF5F7FF'; text = '#FFCDD6F4'; text2 = '#FFBAC2DE'; text3 = '#FFA6ADC8'; text4 = '#FF9399B2'
                  muted = '#FF9399B2'; dim = '#FF7F849C'; faint = '#FF585B70'; off = '#FF45475A'
                  accent = '#FF89B4FA'; accent2 = '#FFB4BEFE' }
    forest   = @{ bg = '#FF111814'; code = '#FF0C120E'; card = '#FF1C2A21'; card2 = '#FF233A2C'
                  textHi = '#FFF0F5F1'; text = '#FFE1EAE3'; text2 = '#FFCFDBD2'; text3 = '#FFAEBFB3'; text4 = '#FF9AAE9F'
                  muted = '#FF86998B'; dim = '#FF66786B'; faint = '#FF4B5B50'; off = '#FF35433A'
                  accent = '#FF5EEAD4'; accent2 = '#FF99F6E4' }
    halloween = @{ bg = '#FF1C1326'; code = '#FF140E1C'; card = '#FF2A1D38'; card2 = '#FF3A2550'
                   textHi = '#FFFFF7ED'; text = '#FFF5E6DA'; text2 = '#FFE7D3C4'; text3 = '#FFC9B3A4'; text4 = '#FFB39E91'
                   muted = '#FFA08B9C'; dim = '#FF7E6A80'; faint = '#FF5B4A63'; off = '#FF3F3048'
                   accent = '#FFF97316'; accent2 = '#FFFDBA74'; pattern = 'halloween' }
    # The main window also gets a moving starfield and planets (lib\space.ps1).
    space    = @{ bg = '#FF0E0820'; code = '#FF09051A'; card = '#FF1C1436'; card2 = '#FF281D4C'
                  textHi = '#FFF5F3FF'; text = '#FFE9E5F8'; text2 = '#FFD6D0EE'; text3 = '#FFB8B0D6'; text4 = '#FFA49BC6'
                  muted = '#FF9A90BE'; dim = '#FF746A99'; faint = '#FF544A78'; off = '#FF3A3160'
                  accent = '#FFA78BFA'; accent2 = '#FFC4B5FD'; pattern = 'space' }
}

# Patterns: a tile of sprites ("." - empty, a letter - a colour), repeated over the window.
$Patterns = @{
    halloween = @{
        tile = 104; px = 2; opacity = 0.1
        colors = @{ o = '#FFF97316'; g = '#FF65A30D'; b = '#FFA78BFA'; w = '#FFF5F5F4'; y = '#FFFDE047' }
        sprites = @(
            @{ x = 6; y = 6; art = @('....gg...', '...g.....', '.ooo.ooo.', 'ooooooooo', 'oo.ooo.oo',
                                     'ooooooooo', 'oo.o.o.oo', '.ooooooo.') }
            @{ x = 58; y = 20; art = @('b.........b', 'bb..b.b..bb', 'bbbbbbbbbbb', '.bbb.b.bbb.', '..b.....b..') }
            @{ x = 30; y = 56; art = @('..www..', '.wwwww.', 'ww.w.ww', 'wwwwwww', 'wwwwwww', 'wwwwwww', 'w.w.w.w') }
            @{ x = 76; y = 70; art = @('.y.', 'yyy', '.y.') }
            @{ x = 8; y = 84; art = @('y') }
            @{ x = 92; y = 4; art = @('y') }
        )
    }
    space = @{
        tile = 96; px = 1; opacity = 0.45
        colors = @{ w = '#FFFFFFFF'; v = '#FFC4B5FD'; p = '#FFF9A8D4'; b = '#FF93C5FD' }
        sprites = @(
            @{ x = 10; y = 8; art = @('w') }; @{ x = 41; y = 22; art = @('v') }; @{ x = 77; y = 12; art = @('b') }
            @{ x = 24; y = 47; art = @('p') }; @{ x = 63; y = 58; art = @('.w.', 'www', '.w.') }
            @{ x = 88; y = 40; art = @('v') }; @{ x = 6; y = 79; art = @('b') }; @{ x = 47; y = 86; art = @('w') }
            @{ x = 83; y = 81; art = @('p') }
        )
    }
}

# The tiled brush of a pattern, drawn once.
$script:PatternBrush = @{}
function Get-PatternBrush([string]$name) {
    if ($script:PatternBrush.ContainsKey($name)) { return $script:PatternBrush[$name] }
    $p = $Patterns[$name]
    $groups = @{}
    foreach ($s in $p.sprites) {
        for ($y = 0; $y -lt $s.art.Count; $y++) {
            for ($x = 0; $x -lt $s.art[$y].Length; $x++) {
                $c = [string]$s.art[$y][$x]
                if (-not $p.colors.ContainsKey($c)) { continue }
                if (-not $groups.ContainsKey($c)) { $groups[$c] = New-Object System.Windows.Media.GeometryGroup }
                $groups[$c].Children.Add([System.Windows.Media.RectangleGeometry]::new(
                    [System.Windows.Rect]::new(($s.x + $x * $p.px), ($s.y + $y * $p.px), $p.px, $p.px)))
            }
        }
    }
    $dg = New-Object System.Windows.Media.DrawingGroup
    # An invisible square sets the tile's size, wherever the sprites are.
    $dg.Children.Add([System.Windows.Media.GeometryDrawing]::new([System.Windows.Media.Brushes]::Transparent, $null,
        [System.Windows.Media.RectangleGeometry]::new([System.Windows.Rect]::new(0, 0, $p.tile, $p.tile))))
    foreach ($c in $groups.Keys) {
        $dg.Children.Add([System.Windows.Media.GeometryDrawing]::new(
            [System.Windows.Media.SolidColorBrush]::new([System.Windows.Media.ColorConverter]::ConvertFromString($p.colors[$c])),
            $null, $groups[$c]))
    }
    $b = New-Object System.Windows.Media.DrawingBrush $dg
    $b.TileMode = 'Tile'
    $b.ViewportUnits = 'Absolute'
    $b.Viewport = [System.Windows.Rect]::new(0, 0, $p.tile, $p.tile)
    $b.Opacity = $p.opacity
    $b.Freeze()
    $script:PatternBrush[$name] = $b
    return $b
}
$script:PatternRects = @()

# Classic colour -> the shared brush; also the resources the XAML refers to.
$script:ThemeBrush = @{}
$ThemeRes = New-Object System.Windows.ResourceDictionary
foreach ($k in $ThemeBase.Keys) {
    $hex = $ThemeBase[$k]
    # Typed: a brush from New-Object is wrapped in a PSObject, and WPF would take the
    # resource for its text "#FF1A1A1E", not a brush.
    [System.Windows.Media.SolidColorBrush]$b = [System.Windows.Media.SolidColorBrush]::new(
        [System.Windows.Media.ColorConverter]::ConvertFromString($hex))
    $script:ThemeBrush[$hex] = $b
    $ThemeRes.Add("theme_$($hex.Substring(1))", $b)
}
$script:ThemeId = ''

# Brush colours in the markup -> {DynamicResource}: attributes and style setters.
# The window then takes $ThemeRes into its resources (Add-ThemeTo).
function Convert-ThemeXaml([string]$xaml) {
    $props = 'Background|Foreground|Fill|Stroke|BorderBrush|CaretBrush|SelectionBrush'
    $sub = {
        param($m)
        $hex = $m.Groups[2].Value.ToUpper()
        if ($script:ThemeBrush.ContainsKey($hex)) { return "$($m.Groups[1].Value)`"{DynamicResource theme_$($hex.Substring(1))}`"" }
        return $m.Value
    }
    $xaml = [regex]::Replace($xaml, "(\b(?:$props)=)`"(#[0-9A-Fa-f]{8})`"", $sub)
    return [regex]::Replace($xaml, "(Property=`"(?:$props)`"\s+Value=)`"(#[0-9A-Fa-f]{8})`"", $sub)
}

# The window takes the theme's brushes; with -Pattern also a layer for the pattern,
# under its content, rounded like the window.
function Add-ThemeTo($window, [switch]$Pattern) {
    $window.Resources.MergedDictionaries.Add($ThemeRes)
    if (-not $Pattern) { return }
    $border = $window.Content
    $grid = New-Object System.Windows.Controls.Grid
    $child = $border.Child
    $border.Child = $null
    $r = New-Object System.Windows.Shapes.Rectangle
    $r.RadiusX = $border.CornerRadius.TopLeft; $r.RadiusY = $r.RadiusX
    $r.IsHitTestVisible = $false
    $r.Margin = New-Object System.Windows.Thickness (-$border.Padding.Left), (-$border.Padding.Top), (-$border.Padding.Right), (-$border.Padding.Bottom)
    [void]$grid.Children.Add($r)
    [void]$grid.Children.Add($child)
    $border.Child = $grid
    $script:PatternRects += $r
    Set-ThemePattern
}

function Set-ThemePattern {
    $name = $Themes[(Get-ThemeId)].pattern
    foreach ($r in $script:PatternRects) {
        if ($name) { $r.Fill = Get-PatternBrush $name; $r.Visibility = 'Visible' }
        else { $r.Visibility = 'Collapsed' }
    }
}

# "auto" (the default) follows the season: Halloween in autumn, classic otherwise.
function Get-SeasonThemeId { if ((Get-Date).Month -in 9..11) { 'halloween' } else { 'classic' } }

function Get-ThemeId {
    $id = ([string]$script:Cfg.theme).ToLower()
    if ($id -eq 'auto') { $id = Get-SeasonThemeId }
    if (-not $Themes.Contains($id)) { $id = 'classic' }
    return $id
}

# Recolours the shared brushes; `accent` in config.json overrides the theme's.
function Set-Theme {
    $id = Get-ThemeId
    $accent = [string]$script:Cfg.accent
    if ("$id|$accent" -eq $script:ThemeId) { return }
    $script:ThemeId = "$id|$accent"
    $t = $Themes[$id]
    foreach ($k in $ThemeBase.Keys) {
        $to = $(if ($t.ContainsKey($k)) { $t[$k] } else { $ThemeBase[$k] })
        if ($k -eq 'accent' -and $accent) { $to = $accent }
        try { $script:ThemeBrush[$ThemeBase[$k]].Color = [System.Windows.Media.ColorConverter]::ConvertFromString($to) } catch {}
    }
    Set-ThemePattern
    # Defined further down the module list; the first Set-Theme runs before it.
    if (Get-Command Sync-Space -ErrorAction SilentlyContinue) { Sync-Space }
}

Set-Theme
