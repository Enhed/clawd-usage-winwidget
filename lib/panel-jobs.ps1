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

# A saved one: name and kind, the text; Run (Stop while a command runs), Change, Delete.
function New-ActCard($a) {
    $card = New-PanelCard $(if ($script:ActEdit -and $a.path -eq $script:ActEdit.path) { '#FF2B3245' } else { '#FF26262C' })
    $box = New-Object System.Windows.Controls.StackPanel
    $run = Get-ActionRun $a.name
    $queued = Test-ActionQueued $a.name
    $kind = "$(if ($a.kind -eq 'command') { [char]0x203A } else { [char]0x2726 }) $(T "act.kind.$($a.kind)")"
    $head = New-PanelText '' 10.5 '#FFF4F4F5'
    $n = New-Object System.Windows.Documents.Run $a.name
    $n.FontWeight = 'SemiBold'
    $head.Inlines.Add($n)
    $k = New-Object System.Windows.Documents.Run "  $([char]0x00B7)  $kind"
    $k.Foreground = New-Brush '#FF6B7280'
    $k.FontSize = 9.5
    $head.Inlines.Add($k)
    if ($run -or $queued) {
        $st = New-Object System.Windows.Documents.Run "  $([char]0x00B7)  $(if ($run) { T 'act.running' } else { T 'task.queued' })"
        $st.Foreground = New-Brush $Palette.warn.Wpf
        $st.FontSize = 9.5
        $head.Inlines.Add($st)
    }
    [void]$box.Children.Add($head)
    $t = New-PanelText ($a.text -replace '\s*\r?\n\s*', ' ') 9.5 '#FF8B8B94'
    if ($a.kind -eq 'command') { $t.FontFamily = 'Consolas' }
    $t.TextWrapping = 'NoWrap'
    $t.TextTrimming = 'CharacterEllipsis'
    $t.ToolTip = $a.text
    $t.Margin = New-Object System.Windows.Thickness 0, 2, 0, 0
    [void]$box.Children.Add($t)
    $row = New-Object System.Windows.Controls.StackPanel
    $row.Orientation = 'Horizontal'
    $row.Margin = New-Object System.Windows.Thickness 0, 4, 0, 0
    if ($run) {
        [void]$row.Children.Add((New-PanelLink (T 'act.stop') $Palette.crit.Wpf $run {
            param($s, $e); $e.Handled = $true; Stop-ActionRun $s.Tag; Update-Panel }))
    } elseif (-not $queued) {
        [void]$row.Children.Add((New-PanelLink (T 'act.run') '#FF4ADE80' $a {
            param($s, $e); $e.Handled = $true; Invoke-Action $s.Tag }))
    }
    [void]$row.Children.Add((New-PanelLink (T 'rem.edit') '#FF8B8B94' $a {
        param($s, $e)
        $e.Handled = $true
        $script:ActEdit = $s.Tag
        $UI.ActName.Text = $s.Tag.name
        $UI.ActText.Text = $s.Tag.text
        Set-ActKind $s.Tag.kind
        [void]$UI.ActText.Focus()
    }))
    [void]$row.Children.Add((New-PanelLink (T 'rem.delete') '#FF6B7280' $a {
        param($s, $e)
        $e.Handled = $true
        try { Remove-Item -LiteralPath $s.Tag.path -Force } catch {}
        if ($script:ActEdit -and $script:ActEdit.path -eq $s.Tag.path) { Reset-ActForm } else { Update-Panel }
    }))
    [void]$box.Children.Add($row)
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
    $key = (Get-Lang) + "|$($script:ActKind)|$($script:ActEdit.path)|$($script:ActShown)|" +
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
