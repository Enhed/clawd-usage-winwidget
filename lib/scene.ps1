# ----------------------------------------------------------------- scene ----
# Animated themes ("scenes"): a backdrop over the whole window, between the theme's
# pattern layer and the content, and a layer in the sky row that takes the
# weather's place. A theme names its scene with `scene = '<id>'`; the scene's module
# (space, ocean, halloween) registers it in $Scenes. Stepped by the mascot's timer.

$Scenes = @{}
$script:Scene = @{ id = ''; tick = 0; broken = @{} }

# The sky row holds the weather's canvas and the scenes' ones side by side.
$skyGrid = New-Object System.Windows.Controls.Grid
$UI.Sky.Child = $null
[void]$skyGrid.Children.Add($UI.SkyFx)
$UI.Sky.Child = $skyGrid

# Add-ThemeTo -Pattern has put a Grid [pattern, content] into the root Border:
# a backdrop goes between the two, clipped to the window's rounded corners.
function New-SceneBackdrop {
    $c = New-Object System.Windows.Controls.Canvas
    $c.IsHitTestVisible = $false
    $c.Visibility = 'Collapsed'
    $c.Margin = $win.Content.Child.Children[0].Margin
    $win.Content.Child.Children.Insert(1, $c)
    $c.add_SizeChanged({
        param($s, $e)
        $r = $win.Content.CornerRadius.TopLeft
        $s.Clip = New-Object System.Windows.Media.RectangleGeometry (
            [System.Windows.Rect]::new(0, 0, $s.ActualWidth, $s.ActualHeight)), $r, $r
    })
    return $c
}

function New-SceneSky {
    $c = New-Object System.Windows.Controls.Canvas
    $c.IsHitTestVisible = $false
    $c.Visibility = 'Collapsed'
    [void]$skyGrid.Children.Add($c)
    return $c
}

# Not New-Brush: a scene's colours are not the theme's, even when the same.
function New-SceneBrush([string]$hex) {
    return New-Object System.Windows.Media.SolidColorBrush (ConvertTo-Color $hex)
}

function New-SceneShape($parent, [string]$kind, [double]$w, [double]$h, $fill) {
    $s = New-Object "System.Windows.Shapes.$kind"
    if ($w) { $s.Width = $w; $s.Height = $h }
    if ($fill) { $s.Fill = $(if ($fill -is [string]) { New-SceneBrush $fill } else { $fill }) }
    [void]$parent.Children.Add($s)
    return $s
}

# A pixel picture: one path per colour letter of the art ("." - empty).
function New-ScenePixels($parent, [string[]]$art, [double]$px, $colors) {
    $c = New-Object System.Windows.Controls.Canvas
    foreach ($k in $colors.Keys) {
        (New-SceneShape $c Path 0 0 $colors[$k]).Data = New-PixelGeo $art $px ([char]$k)
    }
    [void]$parent.Children.Add($c)
    return $c
}

function New-Glow([string]$hex, [double]$a) {
    $c = ConvertTo-Color $hex
    return New-Object System.Windows.Media.RadialGradientBrush (
        [System.Windows.Media.Color]::FromArgb([byte](255 * $a), $c.R, $c.G, $c.B)),
        ([System.Windows.Media.Color]::FromArgb(0, $c.R, $c.G, $c.B))
}

# A vertical fade: $hex at the top, transparent at the bottom.
function New-Fade([string]$hex, [double]$a) {
    $c = ConvertTo-Color $hex
    return New-Object System.Windows.Media.LinearGradientBrush (
        [System.Windows.Media.Color]::FromArgb([byte](255 * $a), $c.R, $c.G, $c.B)),
        ([System.Windows.Media.Color]::FromArgb(0, $c.R, $c.G, $c.B)), 90
}

function Set-At($el, [double]$x, [double]$y) {
    [System.Windows.Controls.Canvas]::SetLeft($el, $x)
    [System.Windows.Controls.Canvas]::SetTop($el, $y)
}

function Get-SceneId {
    $id = [string]$Themes[(Get-ThemeId)].scene
    if (-not $id -or -not $Scenes.ContainsKey($id) -or $script:Scene.broken[$id]) { return '' }
    return $id
}

# Shows the theme's scene and hides the others; with a scene on, the sky row
# trades the weather for it (the sky's own colour would hide the backdrop).
function Sync-Scene {
    $id = Get-SceneId
    $script:Scene.id = $id
    foreach ($k in $Scenes.Keys) {
        $vis = $(if ($k -eq $id) { 'Visible' } else { 'Collapsed' })
        $Scenes[$k].back.Visibility = $vis
        $Scenes[$k].sky.Visibility = $vis
    }
    $UI.SkyFx.Visibility = $(if ($id) { 'Collapsed' } else { 'Visible' })
    $UI.Sky.Background = $(if ($id) { $null } else { $SkyBrush })
    if ($id) { Step-Scene }
}

function Step-Scene {
    $id = $script:Scene.id
    if (-not $id) { return }
    $script:Scene.tick++
    try { & $Scenes[$id].step $script:Scene.tick } catch {
        # A broken scene turns itself off; the theme's colours stay.
        $script:Scene.broken[$id] = $true
        Sync-Scene
        try {
            "$(Get-Date -Format s)`tscene ${id}: $($_.Exception.Message)`t$($_.InvocationInfo.PositionMessage)" |
                Out-File (Join-Path $script:Root 'widget-error.log') -Append -Encoding utf8
        } catch {}
    }
}
