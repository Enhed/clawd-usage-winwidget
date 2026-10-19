# ------------------------------------------------------------ panel jobs ----
# The panel's tabs for what Clawd does: tasks (recurring, a form to add or change
# one) and actions (once, now or at a time: Clawd or a command). The same files
# as everywhere else - tasks.ps1 and actions.ps1 run them.

foreach ($n in @('TaskList', 'TaskName', 'TaskNameHint', 'TaskText', 'TaskTextHint', 'TaskWhen', 'TaskWhenHint',
                 'TaskSave', 'TaskParsed', 'TaskChips', 'ActList', 'ActKinds', 'ActText', 'ActTextHint',
                 'ActWhen', 'ActWhenHint', 'ActSave', 'ActParsed', 'ActChips', 'ActDone')) {
    $UI[$n] = $advWin.FindName($n)
}
$script:TaskKey  = $null
$script:TaskOpen = $null     # the task whose reports are shown
$script:TaskEdit = $null     # task being changed in the form
$script:ActKey   = $null
$script:ActKind  = 'clawd'   # what the form makes
$script:ActEdit  = $null     # planned action being changed
$script:ActShown = ''        # history line whose output is shown: "<time in ticks>|<text>"
$script:ActWhenBad = $null

foreach ($pair in @(@($UI.TaskName, $UI.TaskNameHint), @($UI.TaskText, $UI.TaskTextHint), @($UI.TaskWhen, $UI.TaskWhenHint),
                    @($UI.ActText, $UI.ActTextHint), @($UI.ActWhen, $UI.ActWhenHint))) {
    $pair[0].Tag = $pair[1]
    $pair[0].add_TextChanged({ param($s) $s.Tag.Visibility = $(if ($s.Text) { 'Collapsed' } else { 'Visible' }) })
}

# Enter saves, Shift+Enter - a new line in the text fields; Esc drops a change.
function Add-FormKeys($tb) {
    $tb.add_PreviewKeyDown({
        param($s, $e)
        if ($e.Key -eq [System.Windows.Input.Key]::Return) {
            $e.Handled = $true
            if ($s.AcceptsReturn -and ([System.Windows.Input.Keyboard]::Modifiers -band [System.Windows.Input.ModifierKeys]::Shift)) {
                $i = $s.CaretIndex
                $s.Text = $s.Text.Insert($i, "`n")
                $s.CaretIndex = $i + 1
            } elseif ($s.Name -like 'Task*') { Save-TaskForm2 } else { Save-ActForm }
        } elseif ($e.Key -eq [System.Windows.Input.Key]::Escape) {
            if ($s.Name -like 'Task*') { if ($script:TaskEdit) { $e.Handled = $true; Reset-TaskForm } }
            elseif ($script:ActEdit) { $e.Handled = $true; Reset-ActForm }
        }
    })
}

# ----------------------------------------------------------------- tasks ----

# A recurring task: name, how often, when it last ran; run now, change, pause, open
# the file. A click on the name shows its latest reports, under the links.
function New-TaskRow($t, $st) {
    # A card of its own: the links clearly belong to this task.
    $card = New-PanelCard $(if ($script:TaskEdit -and $script:TaskEdit.name -eq $t.name) { '#FF2B3245' } else { '#FF26262C' })
    $box = New-Object System.Windows.Controls.StackPanel
    $info = @(Format-TaskWhen $t)
    if ($t.hours -and -not $t.at) { $info += "$($t.hours[0])-$($t.hours[1])" }
    $running = ($script:TaskProc -and $script:TaskProc.task.name -eq $t.name)
    $queued = $script:TaskQueue.Contains($t.name)
    if ($running) { $info += T 'task.running' }
    elseif ($queued) { $info += T 'task.queued' }
    elseif ($st -and $st.last -ne [datetime]::MinValue) { $info += (T 'task.last') -f (Format-RemindTime $st.last) }
    if ($t.paused) { $info += T 'task.paused' }
    $wait = Get-TaskBudgetWait $t
    if (-not $t.paused -and $null -ne $wait) { $info += (T 'task.budget') -f $wait }
    $open = ($script:TaskOpen -eq $t.name)
    $arrow = $(if ($open) { [char]0x25BE } else { [char]0x25B8 })
    $line = New-PanelText "$arrow $($t.name)  $([char]0x00B7)  $($info -join "  $([char]0x00B7)  ")" 10 $(if ($t.paused) { '#FF6B7280' } else { '#FFD4D4D8' })
    if ($st -and $st.error) { $line.ToolTip = $st.error; $line.Foreground = New-Brush $Palette.warn.Wpf }
    $line.Cursor = [System.Windows.Input.Cursors]::Hand
    $line.Background = [System.Windows.Media.Brushes]::Transparent
    $line.Tag = $t.name
    $line.add_MouseLeftButtonDown({
        param($s, $e)
        $e.Handled = $true
        $script:TaskOpen = $(if ($script:TaskOpen -eq $s.Tag) { $null } else { $s.Tag })
        $script:TaskKey = $null
        Update-Panel
    })
    [void]$box.Children.Add($line)
    $row = New-Object System.Windows.Controls.WrapPanel
    $row.Margin = New-Object System.Windows.Thickness 0, 3, 0, 0
    if (-not $running -and -not $queued) {
        [void]$row.Children.Add((New-PanelLink (T 'task.now') '#FF60A5FA' $t {
            param($s, $e); $e.Handled = $true; Request-TaskRun $s.Tag; $script:TaskKey = $null; Update-Panel }))
    }
    [void]$row.Children.Add((New-PanelLink (T 'rem.edit') '#FF8B8B94' $t {
        param($s, $e)
        $e.Handled = $true
        $t = $s.Tag
        $script:TaskEdit = $t
        $UI.TaskName.Text = $t.name
        $UI.TaskText.Text = $t.prompt
        $when = $(if ($t.at) { $t.atText } else { $t.everyText })
        if ($t.hours) { $when += " $($t.hours[0])-$($t.hours[1])" }
        $UI.TaskWhen.Text = $when
        $script:TaskKey = $null
        Update-Panel
        [void]$UI.TaskText.Focus()
    }))
    [void]$row.Children.Add((New-PanelLink $(if ($t.paused) { T 'task.resume' } else { T 'task.pause' }) '#FF8B8B94' $t {
        param($s, $e); $e.Handled = $true; Set-TaskPaused $s.Tag (-not $s.Tag.paused); Update-Panel }))
    [void]$row.Children.Add((New-PanelLink (T 'task.open') '#FF8B8B94' $t {
        param($s, $e); $e.Handled = $true; try { Start-Process notepad.exe -ArgumentList "`"$($s.Tag.path)`"" } catch {} }))
    [void]$row.Children.Add((New-PanelLink (T 'rem.delete') '#FF6B7280' $t {
        param($s, $e)
        $e.Handled = $true
        [void](Remove-TaskFile $s.Tag.name)
        if ($script:TaskEdit -and $script:TaskEdit.name -eq $s.Tag.name) { Reset-TaskForm } else { Update-Panel }
    }))
    [void]$box.Children.Add($row)
    if ($open) {
        $hist = @($(if ($st) { $st.history }) | Where-Object { $_ })
        if ($st -and $st.error) { $hist += @{ at = $st.last; text = (T 'task.lastError') -f $st.error; bad = $true } }
        if (-not $hist.Count) {
            $none = New-PanelText (T 'task.noReports') 9.5 '#FF6B7280'
            $none.Margin = New-Object System.Windows.Thickness 0, 4, 0, 0
            [void]$box.Children.Add($none)
        }
        # Newest first, a line per run; what the user was told is brighter. The whole
        # line is in the tooltip.
        foreach ($h in @($hist | Sort-Object { $_.at } -Descending)) {
            $color = $(if ($h.bad) { $Palette.warn.Wpf } elseif ($h.told) { '#FFA1A1AA' } else { '#FF6B7280' })
            $r = New-PanelText "$(Format-RemindTime $h.at)  $([char]0x00B7)  $($h.text)" 9.5 $color
            $r.TextWrapping = 'NoWrap'
            $r.TextTrimming = 'CharacterEllipsis'
            $r.ToolTip = $h.text
            $r.Margin = New-Object System.Windows.Thickness 0, 3, 0, 0
            [void]$box.Children.Add($r)
        }
    }
    $card.Child = $box
    return $card
}

# What the form would make, under it: the schedule as understood, or what is wrong.
function Update-TaskParsed {
    $when = $UI.TaskWhen.Text.Trim()
    $UI.TaskParsed.Foreground = New-Brush '#FF8B8B94'
    if (-not $when) { $UI.TaskParsed.Text = T 'task.permNote'; $UI.TaskParsed.Foreground = New-Brush '#FF6B7280'; return }
    $s = Read-TaskSchedule $when
    if (-not $s) { $UI.TaskParsed.Text = T 'task.badWhen'; $UI.TaskParsed.Foreground = New-Brush $Palette.crit.Wpf; return }
    $txt = "$([char]0x2192) $(Format-TaskWhen $s.sched)"
    if ($s.hoursList -and -not $s.at) { $txt += ", $((T 'task.hoursRange') -f $s.hoursList[0], $s.hoursList[1])" }
    $UI.TaskParsed.Text = $txt
}
$UI.TaskWhen.add_TextChanged({ Update-TaskParsed })

# Named Save-TaskForm2: Save-TaskForm in tasks.ps1 writes the file.
function Save-TaskForm2 {
    $name = ($UI.TaskName.Text -replace '[\\/:*?"<>|\r\n]', ' ' -replace '\s+', ' ').Trim()
    $text = $UI.TaskText.Text.Trim()
    if (-not $name) { [void]$UI.TaskName.Focus(); return }
    if (-not $text) { [void]$UI.TaskText.Focus(); return }
    $s = Read-TaskSchedule $UI.TaskWhen.Text
    if (-not $s) { Update-TaskParsed; [void]$UI.TaskWhen.Focus(); return }
    # A new one must not overwrite another task of the same name.
    $other = Find-Task $name
    if ($other -and -not ($script:TaskEdit -and $script:TaskEdit.path -eq $other.path)) {
        $UI.TaskParsed.Text = T 'task.nameTaken'
        $UI.TaskParsed.Foreground = New-Brush $Palette.crit.Wpf
        [void]$UI.TaskName.Focus()
        return
    }
    $new = Save-TaskForm $name $s $text $script:TaskEdit
    if (-not $new) { return }
    if ($script:TaskEdit -and $script:TaskOpen -eq $script:TaskEdit.name) { $script:TaskOpen = $new }
    Reset-TaskForm
}

function Reset-TaskForm {
    $script:TaskEdit = $null
    $UI.TaskName.Text = ''
    $UI.TaskText.Text = ''
    $UI.TaskWhen.Text = ''
    $script:TaskKey = $null
    Update-Panel
}

$UI.TaskSave.add_MouseLeftButtonDown({ param($s, $e) $e.Handled = $true; Save-TaskForm2 })
foreach ($tb in @($UI.TaskName, $UI.TaskText, $UI.TaskWhen)) { Add-FormKeys $tb }

function Update-TasksPage {
    $tasks = Get-Tasks
    $tst = Load-TaskState
    $key = (Get-Lang) + "|$($script:Cfg.showTasks)|" +
           (@($tasks | ForEach-Object { "$($_.name)$($_.everyText)$($_.atText)$($_.paused)$($_.prompt.Length)$(if ($tst[$_.name]) { "$($tst[$_.name].last.Ticks)$($tst[$_.name].error)" })" }) -join ',') +
           "|$(if ($script:TaskProc) { $script:TaskProc.task.name })|$($script:TaskQueue -join ',')|$($script:TaskOpen)|" +
           (@($tasks | ForEach-Object { Get-TaskBudgetWait $_ }) -join ',') + "|$($script:TaskEdit.path)|" +
           [int]((Get-Date) - [datetime]::Today).TotalMinutes
    if ($key -eq $script:TaskKey) { return }
    $script:TaskKey = $key

    $UI.TaskNameHint.Text = T 'task.nameHint'
    $UI.TaskTextHint.Text = T 'task.textHint'
    $UI.TaskWhenHint.Text = T 'task.whenHint'
    $UI.TaskSave.Text     = $(if ($script:TaskEdit) { T 'rem.save' } else { T 'rem.add' })
    Update-TaskParsed

    $UI.TaskList.Children.Clear()
    if (-not $script:Cfg.showTasks) {
        $off = New-PanelText (T 'task.off') 10 $Palette.warn.Wpf
        $off.Margin = New-Object System.Windows.Thickness 2, 0, 0, 6
        [void]$UI.TaskList.Children.Add($off)
    }
    if (-not $tasks.Count) {
        $none = New-PanelText (T 'task.none') 10 '#FF8B8B94'
        $none.Margin = New-Object System.Windows.Thickness 2, 0, 0, 4
        [void]$UI.TaskList.Children.Add($none)
    }
    foreach ($t in $tasks) { [void]$UI.TaskList.Children.Add((New-TaskRow $t $tst[$t.name])) }

    $UI.TaskChips.Children.Clear()
    foreach ($c in @(T 'task.chips')) {
        [void]$UI.TaskChips.Children.Add((New-PanelLink $c '#FF8B8B94' $c {
            param($s, $e); $e.Handled = $true; $UI.TaskWhen.Text = $s.Tag; [void]$UI.TaskWhen.Focus(); $UI.TaskWhen.CaretIndex = $UI.TaskWhen.Text.Length }))
    }
    if ($script:TaskEdit) {
        [void]$UI.TaskChips.Children.Add((New-PanelLink (T 'rem.cancel') '#FF6B7280' $null {
            param($s, $e); $e.Handled = $true; Reset-TaskForm }))
    }
}

# --------------------------------------------------------------- actions ----

function Update-ActParsed {
    $when = $UI.ActWhen.Text.Trim()
    $UI.ActSave.Text = $(if ($when) { T 'act.plan' } else { T 'act.now' })
    $gray = New-Brush '#FF8B8B94'
    $UI.ActParsed.Foreground = $gray
    if (-not $when) { $UI.ActParsed.Text = T 'act.nowParsed'; return }
    $at = ConvertFrom-RemindWhen $when
    if ($at) {
        $UI.ActParsed.Text = $(if ($at -le (Get-Date)) { T 'act.nowParsed' } else { "$([char]0x2192) $(Format-RemindTime $at)" })
    } elseif (Test-RemRepeat $when) {
        $UI.ActParsed.Text = T 'act.repeat'
        $UI.ActParsed.Foreground = New-Brush '#FF60A5FA'
    } elseif ($script:WhenProc -and $script:WhenProc.when -eq $when) {
        $UI.ActParsed.Text = T 'rem.whenAsking'
    } elseif ($when -eq $script:ActWhenBad) {
        $UI.ActParsed.Text = T 'rem.badWhen'
        $UI.ActParsed.Foreground = New-Brush $Palette.crit.Wpf
    } else {
        $UI.ActParsed.Text = T 'rem.whenAsk'
        $UI.ActParsed.Foreground = New-Brush '#FF6B7280'
    }
}
$UI.ActWhen.add_TextChanged({ Update-ActParsed })

function Save-ActForm {
    $text = $UI.ActText.Text.Trim()
    $when = $UI.ActWhen.Text.Trim()
    if (-not $text) { [void]$UI.ActText.Focus(); return }
    $at = $(if ($when) { ConvertFrom-RemindWhen $when } else { Get-Date })
    if (-not $at) {
        # Every day is a task, not an action.
        if ((Test-RemRepeat $when) -or $when -eq $script:ActWhenBad) { [void]$UI.ActWhen.Focus(); return }
        if (Start-WhenProbe $when @{ action = $true; text = $text; kind = $script:ActKind; edit = $script:ActEdit }) { $whenTimer.Start() }
        Update-ActParsed
        return
    }
    Save-Act $at $script:ActKind $text $script:ActEdit
    Reset-ActForm
}

function Save-Act([datetime]$at, [string]$kind, [string]$text, $edit) {
    if ($edit) { try { Remove-Item -LiteralPath $edit.path -Force } catch {} }
    [void](New-ActionFile $at $kind $text)
    # One for now starts at once, not on the next tick.
    if ($at -le (Get-Date)) { Update-Actions }
}

# Claude's answer about the time, from the reminders' timer (panel-pages.ps1).
function Complete-ActWhen($r) {
    $same = ($UI.ActWhen.Text.Trim() -eq $r.when -and $UI.ActText.Text.Trim() -eq $r.data.text)
    if ($r.at) {
        Save-Act $r.at $r.data.kind $r.data.text $r.data.edit
        if ($same) { Reset-ActForm } else { $script:ActKey = $null; Update-Panel }
    } else {
        $script:ActWhenBad = $r.when
        Update-ActParsed
    }
}

function Reset-ActForm {
    $script:ActEdit = $null
    $UI.ActText.Text = ''
    $UI.ActWhen.Text = ''
    $script:ActKey = $null
    Update-Panel
}

$UI.ActSave.add_MouseLeftButtonDown({ param($s, $e) $e.Handled = $true; Save-ActForm })
foreach ($tb in @($UI.ActText, $UI.ActWhen)) { Add-FormKeys $tb }

function Set-ActKind([string]$kind) {
    $script:ActKind = $kind
    # A command is code: a monospace font.
    $UI.ActText.FontFamily = $(if ($kind -eq 'command') { 'Consolas' } else { 'Segoe UI' })
    $script:ActKey = $null
    Update-Panel
}

# A planned or running one: when, what kind, the text; links to run it now, change, drop or stop.
function New-ActCard($a, $run) {
    $card = New-PanelCard $(if ($script:ActEdit -and $a.path -eq $script:ActEdit.path) { '#FF2B3245' } else { '#FF26262C' })
    $box = New-Object System.Windows.Controls.StackPanel
    $head = New-Object System.Windows.Controls.Grid
    $kind = "$(if ($a.kind -eq 'command') { [char]0x203A } else { [char]0x2726 }) $(T "act.kind.$($a.kind)")"
    $when = $(if ($run) { T 'act.running' } elseif ($a.at -le (Get-Date)) { T $(if ($a.kind -eq 'clawd') { 'act.waitChat' } else { 'act.running' }) }
              else { Format-RemindTime $a.at })
    $w = New-PanelText "$when  $([char]0x00B7)  $kind" 10 $(if ($run) { $Palette.warn.Wpf } else { '#FFF4F4F5' })
    $w.FontWeight = 'SemiBold'
    [void]$head.Children.Add($w)
    $left = $(if (-not $run) { Format-Span $a.at })
    if ($left) {
        $rel = New-PanelText ((T 'rem.in') -f $left) 9.5 '#FF6B7280'
        $rel.HorizontalAlignment = 'Right'
        [void]$head.Children.Add($rel)
    }
    [void]$box.Children.Add($head)
    $t = New-PanelText $a.text 10 '#FFD4D4D8'
    if ($a.kind -eq 'command') { $t.FontFamily = 'Consolas'; $t.FontSize = 9.5 }
    $t.Margin = New-Object System.Windows.Thickness 0, 2, 0, 0
    $t.MaxHeight = 60
    [void]$box.Children.Add($t)
    $row = New-Object System.Windows.Controls.StackPanel
    $row.Orientation = 'Horizontal'
    $row.Margin = New-Object System.Windows.Thickness 0, 4, 0, 0
    if ($run) {
        [void]$row.Children.Add((New-PanelLink (T 'act.stop') $Palette.crit.Wpf $run {
            param($s, $e); $e.Handled = $true; Stop-ActionRun $s.Tag; Update-Panel }))
    } else {
        if ($a.at -gt (Get-Date)) {
            [void]$row.Children.Add((New-PanelLink (T 'task.now') '#FF60A5FA' $a {
                param($s, $e)
                $e.Handled = $true
                try { Remove-Item -LiteralPath $s.Tag.path -Force } catch { return }
                Save-Act (Get-Date) $s.Tag.kind $s.Tag.text $null
                $script:ActKey = $null
                Update-Panel
            }))
        }
        [void]$row.Children.Add((New-PanelLink (T 'rem.edit') '#FF8B8B94' $a {
            param($s, $e)
            $e.Handled = $true
            $script:ActEdit = $s.Tag
            $UI.ActText.Text = $s.Tag.text
            $UI.ActWhen.Text = $(if ($s.Tag.at -gt (Get-Date)) { $s.Tag.at.ToString('dd.MM.yyyy HH:mm') } else { '' })
            Set-ActKind $s.Tag.kind
            [void]$UI.ActText.Focus()
        }))
        [void]$row.Children.Add((New-PanelLink (T 'rem.delete') '#FF6B7280' $a {
            param($s, $e)
            $e.Handled = $true
            try { Remove-Item -LiteralPath $s.Tag.path -Force } catch {}
            if ($script:ActEdit -and $script:ActEdit.path -eq $s.Tag.path) { Reset-ActForm } else { Update-Panel }
        }))
    }
    [void]$box.Children.Add($row)
    $card.Child = $box
    return $card
}

# A line of the history: when, how it went, the text; a click shows a command's
# output, "again" puts it back into the form.
function New-ActDoneRow($h) {
    $box = New-Object System.Windows.Controls.StackPanel
    $box.Margin = New-Object System.Windows.Thickness 0, 3, 0, 0
    $row = New-Object System.Windows.Controls.Grid
    $mark = switch ($h.state) {
        'done'    { @([string][char]0x2713, $Palette.ok.Wpf) }
        'failed'  { @(((T 'act.code') -f $h.code), $Palette.crit.Wpf) }
        'sent'    { @((T 'act.state.sent'), '#FF60A5FA') }
        'missed'  { @((T 'act.state.missed'), $Palette.warn.Wpf) }
        default   { @((T "act.state.$($h.state)"), '#FF8B8B94') }
    }
    $line = New-PanelText '' 10 '#FF8B8B94'
    $line.TextWrapping = 'NoWrap'
    $line.TextTrimming = 'CharacterEllipsis'
    $line.Margin = New-Object System.Windows.Thickness 0, 0, 56, 0
    $line.Inlines.Add((New-Object System.Windows.Documents.Run "$(Format-RemindTime $h.at)  "))
    $m = New-Object System.Windows.Documents.Run $mark[0]
    $m.Foreground = New-Brush $mark[1]
    $line.Inlines.Add($m)
    $line.Inlines.Add((New-Object System.Windows.Documents.Run "  $($h.text -replace '\s+', ' ')"))
    $line.ToolTip = $h.text
    if ($h.kind -eq 'command') {
        $line.Cursor = [System.Windows.Input.Cursors]::Hand
        $line.Background = [System.Windows.Media.Brushes]::Transparent
        $line.Tag = "$($h.at.Ticks)|$($h.text)"
        $line.add_MouseLeftButtonDown({
            param($s, $e)
            $e.Handled = $true
            $script:ActShown = $(if ($script:ActShown -eq $s.Tag) { '' } else { $s.Tag })
            $script:ActKey = $null
            Update-Panel
        })
    }
    [void]$row.Children.Add($line)
    $again = New-PanelLink (T 'rem.again') '#FF60A5FA' $h {
        param($s, $e)
        $e.Handled = $true
        $script:ActEdit = $null
        $UI.ActText.Text = $s.Tag.text
        $UI.ActWhen.Text = ''
        Set-ActKind $(if ($s.Tag.kind -eq 'command') { 'command' } else { 'clawd' })
        [void]$UI.ActText.Focus()
    }
    $again.HorizontalAlignment = 'Right'
    $again.Margin = New-Object System.Windows.Thickness 0
    [void]$row.Children.Add($again)
    [void]$box.Children.Add($row)
    if ($h.kind -eq 'command' -and $script:ActShown -eq "$($h.at.Ticks)|$($h.text)") {
        $out = New-Object System.Windows.Controls.TextBox
        $out.Text            = $(if ($h.output) { $h.output } else { T 'act.noOutput' })
        $out.IsReadOnly      = $true
        $out.FontFamily      = 'Consolas'
        $out.FontSize        = 9.5
        $out.Foreground      = New-Brush '#FFB4B4BC'
        $out.Background      = New-Brush '#FF141416'
        $out.BorderThickness = New-Object System.Windows.Thickness 0
        $out.Padding         = New-Object System.Windows.Thickness 5, 4, 5, 4
        $out.Margin          = New-Object System.Windows.Thickness 0, 3, 0, 2
        $out.TextWrapping    = 'Wrap'
        $out.MaxHeight       = 120
        $out.VerticalScrollBarVisibility = 'Hidden'
        [void]$box.Children.Add($out)
    }
    return $box
}

function Update-ActionsPage {
    $acts = Get-Actions
    $hist = Load-ActionHistory
    $key = (Get-Lang) + "|$($script:ActKind)|$($script:ActEdit.path)|$($script:ActShown)|" +
           (@($acts | ForEach-Object { "$($_.path)$($_.at.Ticks)$($_.kind)" }) -join ',') + '|' +
           (@($script:ActRuns | ForEach-Object { "$($_.act.path)$($_.stopped)" }) -join ',') + "|$([bool]$script:ChatProc)|" +
           (@($hist | ForEach-Object { "$($_.at.Ticks)$($_.state)" }) -join ',') + '|' +
           [int]((Get-Date) - [datetime]::Today).TotalMinutes
    if ($key -eq $script:ActKey) { return }
    $script:ActKey = $key

    $UI.ActTextHint.Text = T "act.textHint.$($script:ActKind)"
    $UI.ActWhenHint.Text = T 'act.whenHint'
    Update-ActParsed

    $UI.ActList.Children.Clear()
    foreach ($r in @($script:ActRuns)) { [void]$UI.ActList.Children.Add((New-ActCard $r.act $r)) }
    foreach ($a in $acts) { [void]$UI.ActList.Children.Add((New-ActCard $a $null)) }
    if (-not $UI.ActList.Children.Count) {
        $none = New-PanelText (T 'act.none') 10 '#FF8B8B94'
        $none.Margin = New-Object System.Windows.Thickness 2, 0, 0, 4
        [void]$UI.ActList.Children.Add($none)
    }

    $UI.ActKinds.Children.Clear()
    foreach ($k in $ActionKinds) {
        [void]$UI.ActKinds.Children.Add((New-ListChip (T "act.kind.$k") ($k -eq $script:ActKind) $k {
            param($s, $e); $e.Handled = $true; Set-ActKind $s.Tag; [void]$UI.ActText.Focus() }))
    }

    $UI.ActChips.Children.Clear()
    foreach ($c in @(T 'act.chips')) {
        [void]$UI.ActChips.Children.Add((New-PanelLink $c '#FF8B8B94' $c {
            param($s, $e); $e.Handled = $true; $UI.ActWhen.Text = $s.Tag; [void]$UI.ActText.Focus() }))
    }
    if ($script:ActEdit) {
        [void]$UI.ActChips.Children.Add((New-PanelLink (T 'rem.cancel') '#FF6B7280' $null {
            param($s, $e); $e.Handled = $true; Reset-ActForm }))
    }

    $UI.ActDone.Children.Clear()
    if ($hist.Count) {
        [void]$UI.ActDone.Children.Add((New-PanelText (T 'rem.done') 9 '#FF6B7280'))
        # Newest first.
        for ($i = $hist.Count - 1; $i -ge [math]::Max(0, $hist.Count - 6); $i--) {
            [void]$UI.ActDone.Children.Add((New-ActDoneRow $hist[$i]))
        }
    }
}
