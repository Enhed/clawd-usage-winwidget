# ----------------------------------------------------------------- skins ----
# Clawd's skins: his colours and pixel accessories on top - a hat, a crown,
# glasses. Built in ones are in the skins folder next to the widget, your own go
# to <clawdHome>\skins (the same name replaces a built in one). A skin is a text file:
#   ---
#   name: Top hat
#   body: #D77757          Clawd's colour (optional)
#   eyes: #141416          the eyes (optional)
#   top: -5                the first art row, counted from Clawd's top row
#   k: #18181B             a colour for each letter of the art
#   ---
#   .......kkkkkk.....
#   ..... (18 pixels wide, as Clawd; "." - empty)
# Without "top" the art sits right on his head. Clawd's own pixel map is in the
# README. The accessories move with him: a hat shows while his head is in the frame,
# what is on the body shows like the body, and lying on his back he loses them all.

$SkinDefault = @{ id = 'classic'; name = ''; body = '#FFD77757'; eyes = '#FF141416'; layers = @() }
$script:Skin = $SkinDefault
$script:SkinPaths = @()

function Get-SkinDirs { return @((Join-Path $script:Root 'skins'), (Join-Path (Get-ClawdHome) 'skins')) }

# A skin file -> @{ id; name; body; eyes; layers = @(@{ color; px = @(@(x, y)) }) }, or $null.
function Read-SkinFile([string]$path) {
    try { $raw = [System.IO.File]::ReadAllText($path, [System.Text.Encoding]::UTF8) } catch { return $null }
    $m = [regex]::Match($raw, '(?s)^\s*---\s*\r?\n(.*?)\r?\n---\s*\r?\n?(.*)$')
    if (-not $m.Success) { return $null }
    $id = [System.IO.Path]::GetFileNameWithoutExtension($path).ToLower()
    $s = @{ id = $id; name = $id; body = $SkinDefault.body; eyes = $SkinDefault.eyes; layers = @() }
    $colors = @{}; $top = $null
    foreach ($line in $m.Groups[1].Value -split '\r?\n') {
        $kv = [regex]::Match($line, '^\s*(\w+)\s*:\s*(.*?)\s*$')
        if (-not $kv.Success) { continue }
        $k = $kv.Groups[1].Value; $v = $kv.Groups[2].Value
        $ok = $v -match '^#([0-9A-Fa-f]{6}|[0-9A-Fa-f]{8})$'
        switch -CaseSensitive ($k) {
            'name' { $s.name = $v }
            'body' { if ($ok) { $s.body = $v } }
            'eyes' { if ($ok) { $s.eyes = $v } }
            'top'  { if ($v -match '^-?\d+$') { $top = [int]$v } }
            default { if ($k.Length -eq 1 -and $ok) { $colors[[string]$k] = $v } }
        }
    }
    $rows = @($m.Groups[2].Value -split '\r?\n' | ForEach-Object { $_.TrimEnd() })
    while ($rows.Count -and -not $rows[-1]) { $rows = @($rows | Select-Object -SkipLast 1) }
    if ($null -eq $top) { $top = -$rows.Count }
    $byColor = @{}
    for ($y = 0; $y -lt $rows.Count; $y++) {
        for ($x = 0; $x -lt [math]::Min($rows[$y].Length, 2 * $ClawdCols); $x++) {
            $c = [string]$rows[$y][$x]
            if (-not $colors.ContainsKey($c)) { continue }
            if (-not $byColor.ContainsKey($c)) { $byColor[$c] = New-Object System.Collections.ArrayList }
            [void]$byColor[$c].Add(@($x, ($top + $y)))
        }
    }
    foreach ($c in $byColor.Keys) { $s.layers += @{ color = $colors[$c]; px = @($byColor[$c]) } }
    return $s
}

# All skins, by id: classic first, then the files (yours over the built in ones).
function Get-Skins {
    $all = [ordered]@{ classic = $SkinDefault }
    foreach ($dir in (Get-SkinDirs)) {
        foreach ($f in @(Get-ChildItem $dir -File -Filter *.txt -ErrorAction SilentlyContinue | Sort-Object Name)) {
            $s = Read-SkinFile $f.FullName
            if ($s) { $all[$s.id] = $s }
        }
    }
    return $all
}

function Get-SkinName($s) {
    return T "skin.$($s.id)" $(if ($s.name) { $s.name } else { $s.id })
}

function New-SkinBrush([string]$hex) {
    # Not New-Brush: Clawd's colours are not the theme's, even when the same.
    return New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.ColorConverter]::ConvertFromString($hex))
}

# The skin from config.json; a file changed on disk counts too, so editing your own
# skin shows at once.
function Set-Skin([switch]$Force) {
    $id = ([string]$script:Cfg.skin).ToLower()
    $all = Get-Skins
    $s = $(if ($all.Contains($id)) { $all[$id] } else { $SkinDefault })
    $key = ConvertTo-Json $s -Depth 6 -Compress
    if (-not $Force -and $key -eq $script:SkinKey) { return }
    $script:SkinKey = $key
    $script:Skin = $s
    $UI.MascotBody.Fill = New-SkinBrush $s.body
    $UI.MascotEyes.Fill = New-SkinBrush $s.eyes
    foreach ($p in $script:SkinPaths) { [void]$UI.Mascot.Children.Remove($p) }
    $script:SkinPaths = @()
    foreach ($l in $s.layers) {
        $p = New-Object System.Windows.Shapes.Path
        $p.Fill = New-SkinBrush $l.color
        $p.IsHitTestVisible = $false
        [void]$UI.Mascot.Children.Add($p)
        $script:SkinPaths += $p
    }
    # Geometry is cached per frame - drawn anew with the accessories.
    $script:MascotGeo = @{}
    $script:Mz.key = $null
}

Set-Skin
