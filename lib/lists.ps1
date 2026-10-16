# ----------------------------------------------------------------- lists ----
# Lists (shopping and any other) are markdown files with checkboxes in Clawd's
# home: lists\<name>.md, items "- [ ] milk" / "- [x] eggs". The panel shows and
# edits them, the chat changes them through `list-*` blocks, Clawd's own session
# (the phone) edits the files himself. Lines that are not items (a heading, notes)
# are kept as they are.

function Get-ListsDir { return Join-Path (Get-ClawdHome) 'lists' }

function Get-ListPath([string]$name) { return Join-Path (Get-ListsDir) "$name.md" }

# List names, the shopping list made on first use so that there is something to fill.
function Get-Lists {
    $dir = Get-ListsDir
    if (-not [System.IO.Directory]::Exists($dir)) {
        try {
            [void][System.IO.Directory]::CreateDirectory($dir)
            New-List (T 'lists.default') | Out-Null
        } catch {}
    }
    $names = @(Get-ChildItem $dir -Filter *.md -File -ErrorAction SilentlyContinue | Sort-Object Name | ForEach-Object { $_.BaseName })
    return ,$names
}

# @{ lines; items = @(@{ idx; done; text }) } - idx is the line number in lines.
function Read-List([string]$name) {
    $lines = @()
    try {
        $raw = [System.IO.File]::ReadAllText((Get-ListPath $name), [System.Text.Encoding]::UTF8)
        $lines = @($raw -split '\r?\n')
        if ($lines.Count -and $lines[-1] -eq '') { $lines = @($lines | Select-Object -First ($lines.Count - 1)) }
    } catch {}
    $items = @()
    for ($i = 0; $i -lt $lines.Count; $i++) {
        $m = [regex]::Match($lines[$i], '^\s*[-*]\s+\[( |x|X)\]\s*(.*)$')
        if ($m.Success) { $items += @{ idx = $i; done = ($m.Groups[1].Value -ne ' '); text = $m.Groups[2].Value.Trim() } }
    }
    return @{ lines = $lines; items = $items }
}

function Save-List([string]$name, $lines) {
    try {
        [void][System.IO.Directory]::CreateDirectory((Get-ListsDir))
        [System.IO.File]::WriteAllText((Get-ListPath $name), (($lines -join "`n") + "`n"),
                                       (New-Object System.Text.UTF8Encoding $false))
    } catch {}
}

# A file name from a list name: what Windows does not allow in one goes.
function Get-ListName([string]$name) {
    return ($name -replace '[\\/:*?"<>|\r\n]', ' ' -replace '\s+', ' ').Trim()
}

function New-List([string]$name) {
    $name = Get-ListName $name
    if (-not $name) { return $null }
    if (-not (Test-Path (Get-ListPath $name))) { Save-List $name @("# $name", '') }
    return $name
}

function Remove-List([string]$name) {
    try { Remove-Item -LiteralPath (Get-ListPath $name) -Force } catch {}
}

# Several at once: "milk, bread" or one per line.
function Add-ListItems([string]$name, [string]$text) {
    $name = New-List $name
    if (-not $name) { return }
    $l = Read-List $name
    $lines = @($l.lines)
    foreach ($t in ($text -split '[,;\r\n]+')) {
        $t = $t.Trim()
        if ($t) { $lines += "- [ ] $t" }
    }
    Save-List $name $lines
}

# The item by its line, or by text (from the chat) - case does not matter.
function Find-ListItem($list, $what) {
    if ($what -is [int]) { return $list.items | Where-Object { $_.idx -eq $what } | Select-Object -First 1 }
    return $list.items | Where-Object { $_.text -eq ([string]$what).Trim() } | Select-Object -First 1
}

function Set-ListItemDone([string]$name, $what, [bool]$done) {
    $l = Read-List $name
    $it = Find-ListItem $l $what
    if (-not $it) { return $false }
    $lines = @($l.lines)
    $lines[$it.idx] = "- [$(if ($done) { 'x' } else { ' ' })] $($it.text)"
    Save-List $name $lines
    return $true
}

function Remove-ListItem([string]$name, $what) {
    $l = Read-List $name
    $it = Find-ListItem $l $what
    if (-not $it) { return $false }
    $lines = @($l.lines)
    Save-List $name @(for ($i = 0; $i -lt $lines.Count; $i++) { if ($i -ne $it.idx) { $lines[$i] } })
    return $true
}

function Clear-ListDone([string]$name) {
    $l = Read-List $name
    $drop = @($l.items | Where-Object { $_.done } | ForEach-Object { $_.idx })
    $lines = @($l.lines)
    Save-List $name @(for ($i = 0; $i -lt $lines.Count; $i++) { if ($drop -notcontains $i) { $lines[$i] } })
}

# When the lists last changed - to redraw the page only then.
function Get-ListsStamp {
    $files = @(Get-ChildItem (Get-ListsDir) -Filter *.md -File -ErrorAction SilentlyContinue)
    return (@($files | ForEach-Object { "$($_.Name)$($_.LastWriteTimeUtc.Ticks)" }) -join '|')
}
