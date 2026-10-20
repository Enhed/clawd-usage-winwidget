# ------------------------------------------------------------ panel jobs ----
# The panel's tabs for what Clawd does: tasks (recurring, a form to add or change
# one) and actions (saved commands and Clawd's mini-skills, run on a click). The
# same files as everywhere else - tasks.ps1 and actions.ps1 run them.

foreach ($n in @('TaskList', 'TaskName', 'TaskNameHint', 'TaskText', 'TaskTextHint', 'TaskWhen', 'TaskWhenHint',
                 'TaskSave', 'TaskParsed', 'TaskChips', 'ActList', 'ActKinds', 'ActName', 'ActNameHint', 'ActText',
                 'ActTextHint', 'ActSave', 'ActRun', 'ActCancel', 'ActParsed', 'ActDone')) {
    $UI[$n] = $advWin.FindName($n)
}
$script:TaskKey  = $null
$script:TaskOpen = $null     # the task whose reports are shown
$script:TaskEdit = $null     # task being changed in the form
$script:ActKey   = $null
$script:ActKind  = 'clawd'   # what the form makes
$script:ActEdit  = $null     # saved action being changed
$script:ActShown = ''        # history line whose output is shown: "<time in ticks>|<text>"
$script:ActOpen  = ''        # saved action whose text is shown

foreach ($pair in @(@($UI.TaskName, $UI.TaskNameHint), @($UI.TaskText, $UI.TaskTextHint), @($UI.TaskWhen, $UI.TaskWhenHint),
                    @($UI.ActName, $UI.ActNameHint), @($UI.ActText, $UI.ActTextHint))) {
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
            } elseif ($s.Name -like 'Task*') { Save-TaskForm2 } else { Submit-ActForm }
        } elseif ($e.Key -eq [System.Windows.Input.Key]::Escape) {
            if ($s.Name -like 'Task*') { if ($script:TaskEdit) { $e.Handled = $true; Reset-TaskForm } }
            elseif ($script:ActEdit) { $e.Handled = $true; Reset-ActForm }
        }
    })
}

# ----------------------------------------------------------------- tasks ----

# An icon button on a card (Segoe MDL2 Assets), with its name as the tooltip.
function New-PanelIcon([int]$glyph, [string]$color, [string]$tip, $tag, $onClick) {
    $i = New-PanelText ([string][char]$glyph) 11 $color
    $i.FontFamily = 'Segoe MDL2 Assets'
    $i.TextWrapping = 'NoWrap'
    $i.VerticalAlignment = 'Center'
    $i.Padding = New-Object System.Windows.Thickness 5, 3, 5, 3
    $i.Margin = New-Object System.Windows.Thickness 2, 0, 0, 0
    $i.Cursor = [System.Windows.Input.Cursors]::Hand
    $i.Background = [System.Windows.Media.Brushes]::Transparent
    $i.ToolTip = $tip
    $i.Tag = $tag
    if ($onClick) { $i.add_MouseLeftButtonDown($onClick) }
    return $i
}

# A recurring task: the name with icons on the right (run now, change, pause, open
# the file, delete), under it how often and when it last ran. A click on the card
# shows its latest reports.
function New-TaskRow($t, $st) {
    $card = New-PanelCard $(if ($script:TaskEdit -and $script:TaskEdit.name -eq $t.name) { '#FF2B3245' } else { '#FF26262C' })
    $card.Padding = New-Object System.Windows.Thickness 9, 4, 4, 5
    $card.Cursor = [System.Windows.Input.Cursors]::Hand
    $card.Tag = $t.name
    $card.add_MouseLeftButtonDown({
        param($s, $e)
        $e.Handled = $true
        $script:TaskOpen = $(if ($script:TaskOpen -eq $s.Tag) { $null } else { $s.Tag })
        $script:TaskKey = $null
        Update-Panel
    })
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

    $head = New-Object System.Windows.Controls.Grid
    $c = New-Object System.Windows.Controls.ColumnDefinition; $head.ColumnDefinitions.Add($c)
    $c = New-Object System.Windows.Controls.ColumnDefinition; $c.Width = 'Auto'; $head.ColumnDefinitions.Add($c)
    $name = New-PanelText $t.name 10.5 $(if ($t.paused) { '#FF8B8B94' } else { '#FFF4F4F5' })
    $name.FontWeight = 'SemiBold'
    $name.TextWrapping = 'NoWrap'
    $name.TextTrimming = 'CharacterEllipsis'
    $name.VerticalAlignment = 'Center'
    [void]$head.Children.Add($name)

    $icons = New-Object System.Windows.Controls.StackPanel
    $icons.Orientation = 'Horizontal'
    [System.Windows.Controls.Grid]::SetColumn($icons, 1)
    if ($running -or $queued) {
        [void]$icons.Children.Add((New-PanelIcon 0xE768 '#FF52525B' $(if ($running) { T 'task.running' } else { T 'task.queued' }) $null {
            param($s, $e); $e.Handled = $true }))
    } else {
        [void]$icons.Children.Add((New-PanelIcon 0xE768 '#FF4ADE80' (T 'task.now') $t {
            param($s, $e); $e.Handled = $true; Request-TaskRun $s.Tag; $script:TaskKey = $null; Update-Panel }))
    }
    [void]$icons.Children.Add((New-PanelIcon 0xE70F '#FF8B8B94' (T 'rem.edit') $t {
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
    # Pause is a toggle: lit while the task is paused.
    $pc = $(if ($t.paused) { $Palette.warn.Wpf } else { '#FF8B8B94' })
    $pt = $(if ($t.paused) { T 'task.resume' } else { T 'task.pause' })
    [void]$icons.Children.Add((New-PanelIcon 0xE769 $pc $pt $t {
        param($s, $e); $e.Handled = $true; Set-TaskPaused $s.Tag (-not $s.Tag.paused); Update-Panel }))
    [void]$icons.Children.Add((New-PanelIcon 0xE8E5 '#FF8B8B94' (T 'task.open') $t {
        param($s, $e); $e.Handled = $true; try { Start-Process notepad.exe -ArgumentList "`"$($s.Tag.path)`"" } catch {} }))
    [void]$icons.Children.Add((New-PanelIcon 0xE74D '#FF6B7280' (T 'rem.delete') $t {
        param($s, $e)
        $e.Handled = $true
        [void](Remove-TaskFile $s.Tag.name)
        if ($script:TaskEdit -and $script:TaskEdit.name -eq $s.Tag.name) { Reset-TaskForm } else { Update-Panel }
    }))
    [void]$head.Children.Add($icons)
    [void]$box.Children.Add($head)

    $line = New-PanelText ($info -join "  $([char]0x00B7)  ") 9.5 $(if ($running) { $Palette.warn.Wpf } else { '#FF8B8B94' })
    $line.Margin = New-Object System.Windows.Thickness 0, 0, 5, 0
    if ($st -and $st.error) { $line.ToolTip = $st.error; $line.Foreground = New-Brush $Palette.warn.Wpf }
    [void]$box.Children.Add($line)

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
            $r.Margin = New-Object System.Windows.Thickness 0, 3, 5, 0
            [void]$box.Children.Add($r)
        }
    }
    $card.Child = $box
    return $card
}

$script:TaskWhenBad = $null   # a "how often" Claude could not make a schedule of either

# What the form would make, under it: the schedule as understood, or what is wrong.
# Something the parser does not know goes to Claude on saving, as with reminders.
function Update-TaskParsed {
    $when = $UI.TaskWhen.Text.Trim()
    $UI.TaskParsed.Foreground = New-Brush '#FF8B8B94'
    if (-not $when) { $UI.TaskParsed.Text = T 'task.permNote'; $UI.TaskParsed.Foreground = New-Brush '#FF6B7280'; return }
    $s = Read-TaskSchedule $when
    if (-not $s) {
        if ($script:WhenProc -and $script:WhenProc.kind -eq 'task' -and $script:WhenProc.when -eq $when) {
            $UI.TaskParsed.Text = T 'rem.whenAsking'
        } elseif ($when -eq $script:TaskWhenBad) {
            $UI.TaskParsed.Text = T 'task.badWhen'
            $UI.TaskParsed.Foreground = New-Brush $Palette.crit.Wpf
        } else {
            $UI.TaskParsed.Text = T 'rem.whenAsk'
            $UI.TaskParsed.Foreground = New-Brush '#FF6B7280'
        }
        return
    }
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
    $when = $UI.TaskWhen.Text.Trim()
    if (-not $when) { [void]$UI.TaskWhen.Focus(); return }
    if (-not (Test-TaskNameFree $name $script:TaskEdit)) { return }
    $s = Read-TaskSchedule $when
    if (-not $s) {
        if ($when -eq $script:TaskWhenBad) { [void]$UI.TaskWhen.Focus(); return }
        if (Start-WhenProbe $when @{ name = $name; text = $text; edit = $script:TaskEdit } 'task') { $taskWhenTimer.Start() }
        Update-TaskParsed
        return
    }
    Save-TaskForm3 $name $s $text $script:TaskEdit
    Reset-TaskForm
}

# A new one must not overwrite another task of the same name.
function Test-TaskNameFree([string]$name, $edit) {
    $other = Find-Task $name
    if (-not $other -or ($edit -and $edit.path -eq $other.path)) { return $true }
    $UI.TaskParsed.Text = T 'task.nameTaken'
    $UI.TaskParsed.Foreground = New-Brush $Palette.crit.Wpf
    [void]$UI.TaskName.Focus()
    return $false
}

function Save-TaskForm3([string]$name, $s, [string]$text, $edit) {
    $new = Save-TaskForm $name $s $text $edit
    if ($new -and $edit -and $script:TaskOpen -eq $edit.name) { $script:TaskOpen = $new }
}

# Claude's schedule. The form is cleared only if it still holds what was asked.
$taskWhenTimer = New-Object System.Windows.Threading.DispatcherTimer
$taskWhenTimer.Interval = [TimeSpan]::FromMilliseconds(500)
$taskWhenTimer.add_Tick({
    try {
        $r = Collect-WhenProbe
        if (-not $r) { return }
        $taskWhenTimer.Stop()
        $d = $r.data
        $same = ($UI.TaskWhen.Text.Trim() -eq $r.when -and $UI.TaskText.Text.Trim() -eq $d.text)
        # Another task may have taken the name while Claude thought.
        $other = Find-Task $d.name
        if ($r.sched -and -not ($other -and -not ($d.edit -and $d.edit.path -eq $other.path))) {
            Save-TaskForm3 $d.name $r.sched $d.text $d.edit
            if ($same) { Reset-TaskForm } else { $script:TaskKey = $null; Update-Panel }
        } elseif ($r.sched) {
            if ($same) { [void](Test-TaskNameFree $d.name $d.edit) }
        } else {
            $script:TaskWhenBad = $r.when
            Update-TaskParsed
        }
    } catch {
        $taskWhenTimer.Stop()
        try {
            "$(Get-Date -Format s)`ttask when: $($_.Exception.Message)`t$($_.InvocationInfo.PositionMessage)" |
                Out-File (Join-Path $script:Root 'widget-error.log') -Append -Encoding utf8
        } catch {}
    }
})

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
    $key = (Get-Lang) + '|' +
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

# Under the form: what is wrong with it, or what Enter does.
function Update-ActParsed([string]$bad = '') {
    $UI.ActNameHint.Text = T 'act.nameHint'
    $UI.ActTextHint.Text = T "act.textHint.$($script:ActKind)"
    $UI.ActSave.Text     = $(if ($script:ActEdit) { T 'rem.save' } else { T 'act.save' })
    $UI.ActRun.Text      = T 'act.run'
    $UI.ActCancel.Text   = T 'rem.cancel'
    $UI.ActCancel.Visibility = $(if ($script:ActEdit) { 'Visible' } else { 'Collapsed' })
    if ($bad) { $UI.ActParsed.Text = $bad; $UI.ActParsed.Foreground = New-Brush $Palette.crit.Wpf; return }
    $UI.ActParsed.Text = $(if ($script:ActKind -eq 'command') { T 'act.noteCommand' } else { T 'act.noteClawd' })
    $UI.ActParsed.Foreground = New-Brush '#FF6B7280'
}

# The form's text, or $null (and the focus where something is missing).
function Get-ActForm([switch]$NeedName) {
    $name = ($UI.ActName.Text -replace '[\\/:*?"<>|\r\n]', ' ' -replace '\s+', ' ').Trim()
    $text = $UI.ActText.Text.Trim()
    if ($NeedName -and -not $name) { [void]$UI.ActName.Focus(); return $null }
    if (-not $text) { [void]$UI.ActText.Focus(); return $null }
    return @{ name = $name; kind = $script:ActKind; text = $text }
}

function Save-ActForm {
    $f = Get-ActForm -NeedName
    if (-not $f) { return }
    # A new one must not overwrite another of the same name.
    $other = Find-Action $f.name
    if ($other -and -not ($script:ActEdit -and $script:ActEdit.path -eq $other.path)) {
        Update-ActParsed (T 'act.nameTaken')
        [void]$UI.ActName.Focus()
        return
    }
    if (Save-ActionFile $f.name $f.kind $f.text $script:ActEdit) { Reset-ActForm }
}

# Run what is in the form once, saved or not: a one-off needs no name.
function Invoke-ActForm {
    $f = Get-ActForm
    if (-not $f) { return }
    if (-not $script:ActEdit) { $f.name = '' }
    Invoke-Action $f
    if (-not $script:ActEdit) { Reset-ActForm }
}

# Enter: with a name - save, without one - just run it.
function Submit-ActForm {
    if ($UI.ActName.Text.Trim()) { Save-ActForm } else { Invoke-ActForm }
}

function Reset-ActForm {
    $script:ActEdit = $null
    $UI.ActName.Text = ''
    $UI.ActText.Text = ''
    $script:ActKey = $null
    Update-Panel
}

$UI.ActSave.add_MouseLeftButtonDown({   param($s, $e) $e.Handled = $true; Save-ActForm })
$UI.ActRun.add_MouseLeftButtonDown({    param($s, $e) $e.Handled = $true; Invoke-ActForm })
$UI.ActCancel.add_MouseLeftButtonDown({ param($s, $e) $e.Handled = $true; Reset-ActForm })
foreach ($tb in @($UI.ActName, $UI.ActText)) { Add-FormKeys $tb }

function Set-ActKind([string]$kind) {
    $script:ActKind = $kind
    # A command is code: a monospace font.
    $UI.ActText.FontFamily = $(if ($kind -eq 'command') { 'Consolas' } else { 'Segoe UI' })
    $script:ActKey = $null
    Update-Panel
}

# A saved one: one line - name and kind, icons on the right: run (stop while a
# command runs), change, delete. A click on the card shows what it does.
function New-ActCard($a) {
    $card = New-PanelCard $(if ($script:ActEdit -and $a.path -eq $script:ActEdit.path) { '#FF2B3245' } else { '#FF26262C' })
    $card.Padding = New-Object System.Windows.Thickness 9, 4, 4, 4
    $card.Cursor = [System.Windows.Input.Cursors]::Hand
    $card.Tag = $a.name
    $card.add_MouseLeftButtonDown({
        param($s, $e)
        $e.Handled = $true
        $script:ActOpen = $(if ($script:ActOpen -eq $s.Tag) { '' } else { $s.Tag })
        $script:ActKey = $null
        Update-Panel
    })
    $run = Get-ActionRun $a.name
    $queued = Test-ActionQueued $a.name
    $open = ($script:ActOpen -eq $a.name)
    $box = New-Object System.Windows.Controls.StackPanel
    $head = New-Object System.Windows.Controls.Grid
    $c = New-Object System.Windows.Controls.ColumnDefinition; $head.ColumnDefinitions.Add($c)
    $c = New-Object System.Windows.Controls.ColumnDefinition; $c.Width = 'Auto'; $head.ColumnDefinitions.Add($c)

    $title = New-PanelText '' 10.5 '#FFF4F4F5'
    $title.TextWrapping = 'NoWrap'
    $title.TextTrimming = 'CharacterEllipsis'
    $title.VerticalAlignment = 'Center'
    # The kind as a mark: a prompt for a command, Clawd's spark for his.
    if ($a.kind -eq 'command') {
        $k = New-Object System.Windows.Documents.Run ([string][char]0xE756)
        $k.FontFamily = 'Segoe MDL2 Assets'
        $k.FontSize = 10
        $k.Foreground = New-Brush '#FF8B8B94'
    } else {
        $k = New-Object System.Windows.Documents.Run ([string][char]0x2726)
        $k.Foreground = New-Brush '#FFD77757'
    }
    $title.Inlines.Add($k)
    $title.Inlines.Add((New-Object System.Windows.Documents.Run '  '))
    $n = New-Object System.Windows.Documents.Run $a.name
    $n.FontWeight = 'SemiBold'
    $title.Inlines.Add($n)
    if ($run -or $queued) {
        $st = New-Object System.Windows.Documents.Run "  $(if ($run) { T 'act.running' } else { T 'task.queued' })"
        $st.Foreground = New-Brush $Palette.warn.Wpf
        $st.FontSize = 9.5
        $title.Inlines.Add($st)
    }
    $title.ToolTip = T "act.kind.$($a.kind)"
    [void]$head.Children.Add($title)

    $icons = New-Object System.Windows.Controls.StackPanel
    $icons.Orientation = 'Horizontal'
    [System.Windows.Controls.Grid]::SetColumn($icons, 1)
    if ($run) {
        [void]$icons.Children.Add((New-PanelIcon 0xE71A $Palette.crit.Wpf (T 'act.stop') $run {
            param($s, $e); $e.Handled = $true; Stop-ActionRun $s.Tag; Update-Panel }))
    } elseif ($queued) {
        [void]$icons.Children.Add((New-PanelIcon 0xE768 '#FF52525B' (T 'task.queued') $null { param($s, $e); $e.Handled = $true }))
    } else {
        [void]$icons.Children.Add((New-PanelIcon 0xE768 '#FF4ADE80' (T 'act.run') $a {
            param($s, $e); $e.Handled = $true; Invoke-Action $s.Tag }))
    }
    [void]$icons.Children.Add((New-PanelIcon 0xE70F '#FF8B8B94' (T 'rem.edit') $a {
        param($s, $e)
        $e.Handled = $true
        $script:ActEdit = $s.Tag
        $UI.ActName.Text = $s.Tag.name
        $UI.ActText.Text = $s.Tag.text
        Set-ActKind $s.Tag.kind
        [void]$UI.ActText.Focus()
    }))
    [void]$icons.Children.Add((New-PanelIcon 0xE74D '#FF6B7280' (T 'rem.delete') $a {
        param($s, $e)
        $e.Handled = $true
        try { Remove-Item -LiteralPath $s.Tag.path -Force } catch {}
        if ($script:ActEdit -and $script:ActEdit.path -eq $s.Tag.path) { Reset-ActForm } else { Update-Panel }
    }))
    [void]$head.Children.Add($icons)
    [void]$box.Children.Add($head)

    if ($open) {
        $t = New-PanelText $a.text 9.5 '#FFA1A1AA'
        if ($a.kind -eq 'command') { $t.FontFamily = 'Consolas' }
        $t.Margin = New-Object System.Windows.Thickness 0, 2, 5, 4
        [void]$box.Children.Add($t)
    }
    $card.Child = $box
    return $card
}

# A line of the history: when, how it went, the name or the text; a click shows a
# command's output, "again" puts a one-off back into the form.
function New-ActDoneRow($h) {
    $id = "$($h.at.Ticks)|$($h.text)"
    $box = New-Object System.Windows.Controls.StackPanel
    $box.Margin = New-Object System.Windows.Thickness 0, 3, 0, 0
    $row = New-Object System.Windows.Controls.Grid
    $mark = switch ($h.state) {
        'done'    { @([string][char]0x2713, $Palette.ok.Wpf) }
        'failed'  { @(((T 'act.code') -f $h.code), $Palette.crit.Wpf) }
        'sent'    { @((T 'act.state.sent'), '#FF60A5FA') }
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
    $line.Inlines.Add((New-Object System.Windows.Documents.Run "  $(if ($h.name) { $h.name } else { $h.text -replace '\s+', ' ' })"))
    $line.ToolTip = $h.text
    if ($h.kind -eq 'command') {
        $line.Cursor = [System.Windows.Input.Cursors]::Hand
        $line.Background = [System.Windows.Media.Brushes]::Transparent
        $line.Tag = $id
        $line.add_MouseLeftButtonDown({
            param($s, $e)
            $e.Handled = $true
            $script:ActShown = $(if ($script:ActShown -eq $s.Tag) { '' } else { $s.Tag })
            $script:ActKey = $null
            Update-Panel
        })
    }
    [void]$row.Children.Add($line)
    # A saved one runs again as it is now; a one-off goes back into the form.
    $again = New-PanelLink (T 'rem.again') '#FF60A5FA' $h {
        param($s, $e)
        $e.Handled = $true
        $a = $(if ($s.Tag.name) { Find-Action $s.Tag.name })
        if ($a) { Invoke-Action $a; return }
        $script:ActEdit = $null
        $UI.ActName.Text = ''
        $UI.ActText.Text = $s.Tag.text
        Set-ActKind $(if ($s.Tag.kind -eq 'command') { 'command' } else { 'clawd' })
        [void]$UI.ActText.Focus()
    }
    $again.HorizontalAlignment = 'Right'
    $again.Margin = New-Object System.Windows.Thickness 0
    [void]$row.Children.Add($again)
    [void]$box.Children.Add($row)
    if ($h.kind -eq 'command' -and $script:ActShown -eq $id) {
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
    $key = (Get-Lang) + "|$($script:ActKind)|$($script:ActEdit.path)|$($script:ActShown)|$($script:ActOpen)|" +
           (@($acts | ForEach-Object { "$($_.name)$($_.kind)$($_.text.Length)" }) -join ',') + '|' +
           (@($script:ActRuns | ForEach-Object { "$($_.act.name)$($_.stopped)" }) -join ',') + '|' +
           (@($script:ActQueue | ForEach-Object { $_.name }) -join ',') + '|' +
           (@($hist | ForEach-Object { "$($_.at.Ticks)$($_.state)" }) -join ',') + '|' +
           [int]((Get-Date) - [datetime]::Today).TotalMinutes
    if ($key -eq $script:ActKey) { return }
    $script:ActKey = $key

    Update-ActParsed

    $UI.ActList.Children.Clear()
    if (-not $acts.Count) {
        $none = New-PanelText (T 'act.none') 10 '#FF8B8B94'
        $none.Margin = New-Object System.Windows.Thickness 2, 0, 0, 4
        [void]$UI.ActList.Children.Add($none)
    }
    foreach ($a in $acts) { [void]$UI.ActList.Children.Add((New-ActCard $a)) }

    $UI.ActKinds.Children.Clear()
    foreach ($k in $ActionKinds) {
        [void]$UI.ActKinds.Children.Add((New-ListChip (T "act.kind.$k") ($k -eq $script:ActKind) $k {
            param($s, $e); $e.Handled = $true; Set-ActKind $s.Tag; [void]$UI.ActText.Focus() }))
    }

    # One-offs running from the form have no card: they show here until they end.
    $UI.ActDone.Children.Clear()
    $loose = @($script:ActRuns | Where-Object { -not $_.act.name })
    if ($hist.Count -or $loose.Count) {
        [void]$UI.ActDone.Children.Add((New-PanelText (T 'rem.done') 9 '#FF6B7280'))
    }
    foreach ($r in $loose) {
        $row = New-Object System.Windows.Controls.Grid
        $row.Margin = New-Object System.Windows.Thickness 0, 3, 0, 0
        $t = New-PanelText "$(T 'act.running')  $($r.act.text -replace '\s+', ' ')" 10 $Palette.warn.Wpf
        $t.TextWrapping = 'NoWrap'
        $t.TextTrimming = 'CharacterEllipsis'
        $t.Margin = New-Object System.Windows.Thickness 0, 0, 70, 0
        [void]$row.Children.Add($t)
        $stop = New-PanelLink (T 'act.stop') $Palette.crit.Wpf $r {
            param($s, $e); $e.Handled = $true; Stop-ActionRun $s.Tag; Update-Panel }
        $stop.HorizontalAlignment = 'Right'
        $stop.Margin = New-Object System.Windows.Thickness 0
        [void]$row.Children.Add($stop)
        [void]$UI.ActDone.Children.Add($row)
    }
    # Newest first.
    for ($i = $hist.Count - 1; $i -ge [math]::Max(0, $hist.Count - 6); $i--) {
        [void]$UI.ActDone.Children.Add((New-ActDoneRow $hist[$i]))
    }
}
