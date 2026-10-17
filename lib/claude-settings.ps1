# ------------------------------------------------------- claude-settings ----
# The "Claude Code" tab of the settings window: a picked set of keys from Claude
# Code's own ~/.claude/settings.json, with what each one does. The file is shared
# with Claude Code: a change rewrites only its own key, keeps every other one as
# it was (order included) and is written the way Claude Code writes it - JSON with
# two-space indents, UTF-8 without BOM. The file as it was before the first change
# of a run is kept next to it as settings.json.clawd-bak.

$script:CcCache    = $null
$script:CcBackedUp = $false

function Get-ClaudeSettingsPath { [System.IO.Path]::Combine((Get-ClaudeConfigDir), 'settings.json') }

# Read anew only when the file has changed: @{ obj; err; stamp }.
function Get-ClaudeSettings {
    $file = Get-ClaudeSettingsPath
    $stamp = ''
    try { if ([System.IO.File]::Exists($file)) { $stamp = [string][System.IO.File]::GetLastWriteTimeUtc($file).Ticks } } catch {}
    if ($script:CcCache -and $script:CcCache.stamp -eq $stamp) { return $script:CcCache }
    $c = @{ obj = (New-Object PSObject); err = $null; stamp = $stamp }
    if ($stamp) {
        try {
            $text = [System.IO.File]::ReadAllText($file)
            if ($text.Trim()) { $c.obj = $text | ConvertFrom-Json -ErrorAction Stop }
            if ($c.obj -isnot [System.Management.Automation.PSCustomObject]) { throw 'not a JSON object' }
        } catch {
            $c.obj = New-Object PSObject
            $c.err = $_.Exception.Message
        }
    }
    $script:CcCache = $c
    return $c
}

# 'permissions.defaultMode' -> its value, $null when the key is not there.
function Get-ClaudeSetting([string]$path) {
    $cur = (Get-ClaudeSettings).obj
    foreach ($part in $path.Split('.')) {
        if ($cur -isnot [System.Management.Automation.PSCustomObject]) { return $null }
        $p = $cur.PSObject.Properties[$part]
        if (-not $p) { return $null }
        $cur = $p.Value
    }
    return $cur
}

function ConvertTo-CcString([string]$s) {
    $sb = New-Object System.Text.StringBuilder ($s.Length + 2)
    [void]$sb.Append('"')
    foreach ($ch in $s.ToCharArray()) {
        $n = [int]$ch
        if     ($ch -eq '"')  { [void]$sb.Append('\"') }
        elseif ($ch -eq '\')  { [void]$sb.Append('\\') }
        elseif ($n -eq 10)    { [void]$sb.Append('\n') }
        elseif ($n -eq 13)    { [void]$sb.Append('\r') }
        elseif ($n -eq 9)     { [void]$sb.Append('\t') }
        elseif ($n -eq 8)     { [void]$sb.Append('\b') }
        elseif ($n -eq 12)    { [void]$sb.Append('\f') }
        elseif ($n -lt 0x20)  { [void]$sb.Append(('\u{0:x4}' -f $n)) }
        else                  { [void]$sb.Append($ch) }
    }
    [void]$sb.Append('"')
    return $sb.ToString()
}

# JSON.stringify(value, null, 2): what ConvertTo-Json of PowerShell 5.1 is not -
# it cuts nesting off at -Depth, escapes < > ' and indents in its own way.
function ConvertTo-CcJson($v, [string]$ind = '') {
    if ($null -eq $v) { return 'null' }
    if ($v -is [bool]) { if ($v) { return 'true' } else { return 'false' } }
    if ($v -is [string]) { return ConvertTo-CcString $v }
    $inv = [System.Globalization.CultureInfo]::InvariantCulture
    if ($v -is [double] -or $v -is [single]) { return $v.ToString('R', $inv) }
    if ($v -is [System.ValueType]) { return [System.Convert]::ToString($v, $inv) }
    $in2 = $ind + '  '
    if ($v -is [System.Collections.IList]) {
        if ($v.Count -eq 0) { return '[]' }
        $items = foreach ($x in $v) { $in2 + (ConvertTo-CcJson $x $in2) }
        return "[`n" + ($items -join ",`n") + "`n$ind]"
    }
    $props = @($v.PSObject.Properties | Where-Object { $_.MemberType -eq 'NoteProperty' })
    if ($props.Count -eq 0) { return '{}' }
    $items = foreach ($p in $props) { $in2 + (ConvertTo-CcString $p.Name) + ': ' + (ConvertTo-CcJson $p.Value $in2) }
    return "{`n" + ($items -join ",`n") + "`n$ind}"
}

# Several keys in one write: @{ 'attribution.commit' = '' }; $null removes the key,
# and an object left empty by that goes too.
function Set-ClaudeSettings([hashtable]$changes) {
    $c = Get-ClaudeSettings
    if ($c.err) { return }
    $o = $c.obj
    foreach ($path in $changes.Keys) {
        $value = $changes[$path]
        $parts = $path.Split('.')
        $chain = @($o)
        $cur = $o
        for ($i = 0; $i -lt $parts.Count - 1; $i++) {
            $p = $cur.PSObject.Properties[$parts[$i]]
            if (-not $p -or $p.Value -isnot [System.Management.Automation.PSCustomObject]) {
                if ($null -eq $value) { $cur = $null; break }
                Add-Member -InputObject $cur -NotePropertyName $parts[$i] -NotePropertyValue (New-Object PSObject) -Force
                $p = $cur.PSObject.Properties[$parts[$i]]
            }
            $cur = $p.Value
            $chain += $cur
        }
        if ($null -eq $cur) { continue }
        $last = $parts[-1]
        if ($null -eq $value) {
            $cur.PSObject.Properties.Remove($last)
            for ($i = $chain.Count - 1; $i -gt 0; $i--) {
                if (@($chain[$i].PSObject.Properties).Count) { break }
                $chain[$i - 1].PSObject.Properties.Remove($parts[$i - 1])
            }
        } elseif ($cur.PSObject.Properties[$last]) {
            $cur.PSObject.Properties[$last].Value = $value
        } else {
            Add-Member -InputObject $cur -NotePropertyName $last -NotePropertyValue $value
        }
    }
    $file = Get-ClaudeSettingsPath
    try {
        if (-not $script:CcBackedUp -and [System.IO.File]::Exists($file)) {
            [System.IO.File]::Copy($file, "$file.clawd-bak", $true)
            $script:CcBackedUp = $true
        }
        [void][System.IO.Directory]::CreateDirectory((Split-Path $file))
        $tmp = "$file.clawd-tmp"
        [System.IO.File]::WriteAllText($tmp, (ConvertTo-CcJson $o) + "`n", (New-Object System.Text.UTF8Encoding $false))
        # [NullString]: a plain $null would come in as '' - "the path is not of a legal form".
        if ([System.IO.File]::Exists($file)) { [System.IO.File]::Replace($tmp, $file, [NullString]::Value) }
        else { [System.IO.File]::Move($tmp, $file) }
    } catch {
        "$(Get-Date -Format s) settings.json: $($_.Exception.Message)" |
            Out-File (Join-Path $script:Root 'widget-error.log') -Append -Encoding utf8
    }
    $script:CcCache = $null
    $script:SetKey = $null
    Update-Settings
}

function Set-ClaudeSetting([string]$path, $value) { Set-ClaudeSettings @{ $path = $value } }

# The tab: what is shown and how. toggle - yes/no with its default when the key is
# not there; choice - chips, '' among them removes the key, a value of the file that
# is not among them gets a chip of its own; days - a stepper.
$ClaudeItems = @(
    @{ head = 'cc.hModel' }
    @{ k = 'model'; t = 'choice'; opts = @('', 'opus', 'sonnet', 'haiku', 'fable') }
    @{ k = 'fastMode'; t = 'toggle'; def = $false }
    @{ k = 'language'; t = 'choice'; opts = @('', 'english', 'russian', 'french') }
    @{ k = 'permissions.defaultMode'; t = 'choice'; opts = @('default', 'acceptEdits', 'plan', 'auto'); def = 'default' }
    @{ head = 'cc.hWork' }
    @{ k = 'autoCompactEnabled'; t = 'toggle'; def = $true }
    @{ k = 'autoMemoryEnabled'; t = 'toggle'; def = $true }
    @{ k = 'fileCheckpointingEnabled'; t = 'toggle'; def = $true }
    @{ k = 'awaySummaryEnabled'; t = 'toggle'; def = $true }
    @{ k = 'respondToBashCommands'; t = 'toggle'; def = $true }
    @{ k = 'attribution'; t = 'attribution' }
    @{ k = 'cleanupPeriodDays'; t = 'days'; def = 30; steps = @(7, 14, 30, 60, 90, 180, 365) }
    @{ k = 'autoUpdatesChannel'; t = 'choice'; opts = @('latest', 'stable'); def = 'latest' }
    @{ head = 'cc.hTerminal' }
    @{ k = 'theme'; t = 'choice'; opts = @('auto', 'dark', 'light', 'dark-daltonized', 'light-daltonized', 'dark-ansi', 'light-ansi'); def = 'dark' }
    @{ k = 'tui'; t = 'choice'; opts = @('', 'fullscreen', 'default') }
    @{ k = 'outputStyle'; t = 'choice'; opts = @('', 'Proactive', 'Explanatory', 'Learning') }
    @{ k = 'viewMode'; t = 'choice'; opts = @('', 'default', 'verbose', 'focus') }
    @{ k = 'editorMode'; t = 'choice'; opts = @('normal', 'vim'); def = 'normal' }
    @{ k = 'spinnerTipsEnabled'; t = 'toggle'; def = $true }
    @{ k = 'showTurnDuration'; t = 'toggle'; def = $true }
    @{ k = 'showThinkingSummaries'; t = 'toggle'; def = $false }
    @{ k = 'terminalProgressBarEnabled'; t = 'toggle'; def = $true }
    @{ k = 'prefersReducedMotion'; t = 'toggle'; def = $false }
    @{ head = 'cc.hRemote' }
    @{ k = 'remoteControlAtStartup'; t = 'toggle'; def = $false }
    @{ k = 'agentPushNotifEnabled'; t = 'toggle'; def = $false }
    @{ k = 'inputNeededNotifEnabled'; t = 'toggle'; def = $false }
)

function New-ClaudeChoice($it) {
    $box = New-Object System.Windows.Controls.StackPanel
    $box.Margin = New-Object System.Windows.Thickness 0, 0, 0, 4
    $l = New-PanelText (T "cc.$($it.k)") 10.5 '#FFE4E4E7'
    $l.Margin = New-Object System.Windows.Thickness 0, 0, 0, 3
    $tip = T "cc.$($it.k).tip" ''
    if ($tip) { $l.ToolTip = $tip }
    [void]$box.Children.Add($l)
    $cur = Get-ClaudeSetting $it.k
    $shown = $(if ($null -ne $cur) { [string]$cur } elseif ($it.def) { $it.def } else { '' })
    $opts = @($it.opts)
    if ($null -ne $cur -and -not ($opts -contains [string]$cur)) { $opts += [string]$cur }
    $wrap = New-Object System.Windows.Controls.WrapPanel
    foreach ($v in $opts) {
        $text = $(if ($v -eq '') { T 'cc.unset' } else { T "cc.$($it.k).$v" $v })
        [void]$wrap.Children.Add((New-ListChip $text ($v -eq $shown) @($it.k, $v) {
            param($s, $e)
            $e.Handled = $true
            $v = $s.Tag[1]
            Set-ClaudeSetting $s.Tag[0] $(if ($v -eq '') { $null } else { $v })
        }))
    }
    [void]$box.Children.Add($wrap)
    return $box
}

function Add-SetClaudePage($p) {
    $c = Get-ClaudeSettings
    $path = Get-ClaudeSettingsPath
    if ($path.StartsWith($env:USERPROFILE + '', [System.StringComparison]::OrdinalIgnoreCase)) { $path = '~' + $path.Substring($env:USERPROFILE.Length) }
    # A word joiner after the slash: WPF would wrap /config as "/" and "config".
    $note = New-PanelText (((T 'cc.note') -f $path) -replace '/(?=\w)', "/$([char]0x2060)") 9.5 '#FF8B8B94'
    $note.Margin = New-Object System.Windows.Thickness 0, 0, 0, 4
    [void]$p.Children.Add($note)
    if ($c.err) {
        $t = New-PanelText ((T 'cc.bad') -f $c.err) 10 '#FFF87171'
        $t.Margin = New-Object System.Windows.Thickness 0, 4, 0, 0
        [void]$p.Children.Add($t)
        return
    }
    foreach ($it in $ClaudeItems) {
        if ($it.head) { [void]$p.Children.Add((New-SetHeader (T $it.head))); continue }
        $tip = T "cc.$($it.k).tip" ''
        switch ($it.t) {
            'toggle' {
                $cur = Get-ClaudeSetting $it.k
                $on = $(if ($null -eq $cur) { $it.def } else { [bool]$cur })
                [void]$p.Children.Add((New-SetSwitch (T "cc.$($it.k)") $on $tip @($it.k, $on) {
                    param($s, $e)
                    $e.Handled = $true
                    Set-ClaudeSetting $s.Tag[0] (-not $s.Tag[1])
                }))
            }
            'attribution' {
                $on = ([string](Get-ClaudeSetting 'attribution.commit') -ne '' -or $null -eq (Get-ClaudeSetting 'attribution.commit'))
                [void]$p.Children.Add((New-SetSwitch (T 'cc.attribution') $on $tip $on {
                    param($s, $e)
                    $e.Handled = $true
                    if ($s.Tag) { Set-ClaudeSettings @{ 'attribution.commit' = ''; 'attribution.pr' = '' } }
                    else        { Set-ClaudeSettings @{ 'attribution.commit' = $null; 'attribution.pr' = $null } }
                }))
            }
            'days' {
                $cur = Get-ClaudeSetting $it.k
                $n = $(if ($null -eq $cur) { $it.def } else { [int]$cur })
                $row = New-SetStepper (T "cc.$($it.k)") ((T 'cc.days') -f $n) {
                    param($s, $e); $e.Handled = $true
                    $n = [int]$s.Tag
                    $lower = @($ClaudeItems | Where-Object { $_.k -eq 'cleanupPeriodDays' })[0].steps | Where-Object { $_ -lt $n }
                    if ($lower) { Set-ClaudeSetting 'cleanupPeriodDays' ([int]@($lower)[-1]) }
                } {
                    param($s, $e); $e.Handled = $true
                    $n = [int]$s.Tag
                    $higher = @($ClaudeItems | Where-Object { $_.k -eq 'cleanupPeriodDays' })[0].steps | Where-Object { $_ -gt $n }
                    if ($higher) { Set-ClaudeSetting 'cleanupPeriodDays' ([int]@($higher)[0]) }
                }
                foreach ($b in $row.Children[1].Children) { $b.Tag = $n }
                if ($tip) { $row.ToolTip = $tip }
                [void]$p.Children.Add($row)
            }
            'choice' { [void]$p.Children.Add((New-ClaudeChoice $it)) }
        }
    }
}
