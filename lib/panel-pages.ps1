# ----------------------------------------------------------- panel pages ----
# The panel's tabs besides the chat: reminders (upcoming, a form to add or change
# one, recently fired) and lists (shopping and others, with checkboxes). Both are
# the same files Clawd works with, so changes made anywhere show up here.

foreach ($n in @('TabChat', 'TabRemind', 'TabLists', 'PageChat', 'PageRemind', 'PageLists',
                 'RemList', 'RemText', 'RemTextHint', 'RemWhen', 'RemWhenHint', 'RemSave', 'RemParsed',
                 'RemChips', 'RemDone', 'ListTabs', 'ListItems', 'ListAdd', 'ListAddHint', 'ListClear', 'ListDelete')) {
    $UI[$n] = $advWin.FindName($n)
}
$script:PanelTab = 'chat'
$script:RemEdit  = $null     # reminder being changed in the form
$script:RemKey   = $null
$script:ListCur  = $null     # list shown
$script:ListNew  = $false    # the add field takes a new list's name
$script:ListKey  = $null

function Set-PanelTab([string]$tab) {
    $script:PanelTab = $tab
    $UI.PageChat.Visibility   = $(if ($tab -eq 'chat')   { 'Visible' } else { 'Collapsed' })
    $UI.PageRemind.Visibility = $(if ($tab -eq 'remind') { 'Visible' } else { 'Collapsed' })
    $UI.PageLists.Visibility  = $(if ($tab -eq 'lists')  { 'Visible' } else { 'Collapsed' })
    # Rescan and "new conversation" are about the chat.
    foreach ($b in @($UI.AdvStamp, $UI.AdvRescan, $UI.ChatNew)) {
        $b.Visibility = $(if ($tab -eq 'chat') { 'Visible' } else { 'Collapsed' })
    }
    Update-PanelTabs
    $script:RemKey = $null; $script:ListKey = $null
    Update-Panel -Force
}

function Update-PanelTabs {
    $n = (Get-Reminders).Count
    $UI.TabChat.Text   = T 'tab.chat'
    $UI.TabRemind.Text = $(if ($n) { "$(T 'tab.remind')  $n" } else { T 'tab.remind' })
    $UI.TabLists.Text  = T 'tab.lists'
    foreach ($p in @(@($UI.TabChat, 'chat'), @($UI.TabRemind, 'remind'), @($UI.TabLists, 'lists'))) {
        $on = ($p[1] -eq $script:PanelTab)
        $p[0].Foreground = New-Brush $(if ($on) { '#FFF4F4F5' } else { '#FF6B7280' })
        # Assigned directly: through $( ) PowerShell would unroll the collection into one item.
        if ($on) { $p[0].TextDecorations = [System.Windows.TextDecorations]::Underline }
        else     { $p[0].TextDecorations = $null }
    }
}

$UI.TabChat.add_MouseLeftButtonDown({   param($s, $e) $e.Handled = $true; Set-PanelTab 'chat' })
$UI.TabRemind.add_MouseLeftButtonDown({ param($s, $e) $e.Handled = $true; Set-PanelTab 'remind' })
$UI.TabLists.add_MouseLeftButtonDown({  param($s, $e) $e.Handled = $true; Set-PanelTab 'lists' })

# A hint over an empty field, as in the chat.
foreach ($pair in @(@($UI.RemText, $UI.RemTextHint), @($UI.RemWhen, $UI.RemWhenHint), @($UI.ListAdd, $UI.ListAddHint))) {
    $pair[0].Tag = $pair[1]
    $pair[0].add_TextChanged({ param($s) $s.Tag.Visibility = $(if ($s.Text) { 'Collapsed' } else { 'Visible' }) })
}

# ------------------------------------------------------------- reminders ----

function Update-RemParsed {
    $when = $UI.RemWhen.Text.Trim()
    if (-not $when) { $UI.RemParsed.Text = ''; return }
    $at = ConvertFrom-RemindWhen $when
    if ($at) {
        $UI.RemParsed.Text = "$([char]0x2192) $(Format-RemindTime $at)"
        $UI.RemParsed.Foreground = New-Brush '#FF8B8B94'
    } else {
        $UI.RemParsed.Text = T 'rem.badWhen'
        $UI.RemParsed.Foreground = New-Brush $Palette.crit.Wpf
    }
}
$UI.RemWhen.add_TextChanged({ Update-RemParsed })

function Save-RemForm {
    $text = $UI.RemText.Text.Trim()
    $at = ConvertFrom-RemindWhen $UI.RemWhen.Text
    if (-not $text) { [void]$UI.RemText.Focus(); return }
    if (-not $at) { Update-RemParsed; [void]$UI.RemWhen.Focus(); return }
    if ($script:RemEdit) { [void](Move-Reminder $script:RemEdit $at $text) }
    else                 { [void](New-ReminderFile $at $text) }
    Reset-RemForm
}

function Reset-RemForm {
    $script:RemEdit = $null
    $UI.RemText.Text = ''
    $UI.RemWhen.Text = ''
    $script:RemKey = $null
    Update-Panel
}

$UI.RemSave.add_MouseLeftButtonDown({ param($s, $e) $e.Handled = $true; Save-RemForm })
foreach ($tb in @($UI.RemText, $UI.RemWhen)) {
    $tb.add_PreviewKeyDown({
        param($s, $e)
        if ($e.Key -eq [System.Windows.Input.Key]::Return) { $e.Handled = $true; Save-RemForm }
        elseif ($e.Key -eq [System.Windows.Input.Key]::Escape -and $script:RemEdit) { $e.Handled = $true; Reset-RemForm }
    })
}

function New-RemCard($r) {
    $card = New-PanelCard '#FF26262C'
    $box = New-Object System.Windows.Controls.StackPanel
    $head = New-Object System.Windows.Controls.Grid
    $when = New-PanelText (Format-RemindTime $r.at) 10.5 '#FFF4F4F5'
    $when.FontWeight = 'SemiBold'
    [void]$head.Children.Add($when)
    $left = Format-Span $r.at
    if ($left) {
        $rel = New-PanelText ((T 'rem.in') -f $left) 9.5 '#FF6B7280'
        $rel.HorizontalAlignment = 'Right'
        [void]$head.Children.Add($rel)
    }
    [void]$box.Children.Add($head)
    $t = New-PanelText $r.text
    $t.Margin = New-Object System.Windows.Thickness 0, 2, 0, 0
    [void]$box.Children.Add($t)
    $row = New-Object System.Windows.Controls.StackPanel
    $row.Orientation = 'Horizontal'
    $row.Margin = New-Object System.Windows.Thickness 0, 4, 0, 0
    [void]$row.Children.Add((New-PanelLink (T 'rem.edit') '#FF60A5FA' $r {
        param($s, $e)
        $e.Handled = $true
        $script:RemEdit = $s.Tag
        $UI.RemText.Text = $s.Tag.text
        $UI.RemWhen.Text = $s.Tag.at.ToString('dd.MM.yyyy HH:mm')
        $script:RemKey = $null
        Update-Panel
        [void]$UI.RemText.Focus()
    }))
    [void]$row.Children.Add((New-PanelLink (T 'rem.later') '#FF8B8B94' $r {
        param($s, $e)
        $e.Handled = $true
        # Later from now if it is due already, from its time otherwise.
        $base = $(if ($s.Tag.at -gt (Get-Date)) { $s.Tag.at } else { Get-Date })
        [void](Move-Reminder $s.Tag $base.AddHours(1))
        Update-Panel
    }))
    [void]$row.Children.Add((New-PanelLink (T 'rem.delete') '#FF6B7280' $r {
        param($s, $e)
        $e.Handled = $true
        try { Remove-Item -LiteralPath $s.Tag.path -Force } catch {}
        if ($script:RemEdit -and $script:RemEdit.path -eq $s.Tag.path) { Reset-RemForm } else { Update-Panel }
    }))
    [void]$box.Children.Add($row)
    $card.Child = $box
    return $card
}

function Update-RemindPage {
    $rem = Get-Reminders
    $done = Get-DoneReminders 5
    $key = (Get-Lang) + '|' + (@($rem | ForEach-Object { "$($_.path)$($_.at.Ticks)" }) -join ',') + '|' +
           (@($done | ForEach-Object { "$($_.at.Ticks)$($_.text)" }) -join ',') + "|$($script:RemEdit.path)|" +
           [int]((Get-Date) - [datetime]::Today).TotalMinutes    # "in 2 h" goes stale
    if ($key -eq $script:RemKey) { return }
    $script:RemKey = $key

    $UI.RemTextHint.Text = T 'rem.textHint'
    $UI.RemWhenHint.Text = T 'rem.whenHint'
    $UI.RemSave.Text     = $(if ($script:RemEdit) { T 'rem.save' } else { T 'rem.add' })

    $UI.RemList.Children.Clear()
    if (-not $rem.Count) {
        $none = New-PanelText (T 'rem.none') 10 '#FF8B8B94'
        $none.Margin = New-Object System.Windows.Thickness 2, 0, 0, 4
        [void]$UI.RemList.Children.Add($none)
    }
    foreach ($r in $rem) { [void]$UI.RemList.Children.Add((New-RemCard $r)) }

    # Quick "when"; while changing one - also a way back.
    $UI.RemChips.Children.Clear()
    foreach ($c in @(T 'rem.chips')) {
        [void]$UI.RemChips.Children.Add((New-PanelLink $c '#FF8B8B94' $c {
            param($s, $e); $e.Handled = $true; $UI.RemWhen.Text = $s.Tag; [void]$UI.RemText.Focus() }))
    }
    if ($script:RemEdit) {
        [void]$UI.RemChips.Children.Add((New-PanelLink (T 'rem.cancel') '#FF6B7280' $null {
            param($s, $e); $e.Handled = $true; Reset-RemForm }))
    }

    $UI.RemDone.Children.Clear()
    if ($done.Count) {
        [void]$UI.RemDone.Children.Add((New-PanelText (T 'rem.done') 9 '#FF6B7280'))
        foreach ($d in $done) {
            $row = New-Object System.Windows.Controls.Grid
            $row.Margin = New-Object System.Windows.Thickness 0, 3, 0, 0
            $t = New-PanelText "$(Format-RemindTime $d.at)  $([char]0x00B7)  $($d.text)" 10 '#FF6B7280'
            $t.TextTrimming = 'CharacterEllipsis'
            $t.TextWrapping = 'NoWrap'
            $t.Margin = New-Object System.Windows.Thickness 0, 0, 56, 0
            [void]$row.Children.Add($t)
            $again = New-PanelLink (T 'rem.again') '#FF60A5FA' $d.text {
                param($s, $e); $e.Handled = $true; $UI.RemText.Text = $s.Tag; [void]$UI.RemWhen.Focus() }
            $again.HorizontalAlignment = 'Right'
            $again.Margin = New-Object System.Windows.Thickness 0
            [void]$row.Children.Add($again)
            [void]$UI.RemDone.Children.Add($row)
        }
    }
}

# ----------------------------------------------------------------- lists ----

function Submit-ListAdd {
    $t = $UI.ListAdd.Text.Trim()
    if (-not $t) { return }
    $UI.ListAdd.Text = ''
    if ($script:ListNew) {
        $script:ListNew = $false
        $name = New-List $t
        if ($name) { $script:ListCur = $name }
    } else {
        Add-ListItems $script:ListCur $t
    }
    $script:ListKey = $null
    Update-Panel
}
$UI.ListAdd.add_PreviewKeyDown({
    param($s, $e)
    if ($e.Key -eq [System.Windows.Input.Key]::Return) { $e.Handled = $true; Submit-ListAdd }
    elseif ($e.Key -eq [System.Windows.Input.Key]::Escape -and $script:ListNew) {
        $e.Handled = $true; $script:ListNew = $false; $UI.ListAdd.Text = ''; $script:ListKey = $null; Update-Panel }
})
$UI.ListClear.add_MouseLeftButtonDown({ param($s, $e) $e.Handled = $true; Clear-ListDone $script:ListCur; Update-Panel })
$UI.ListDelete.add_MouseLeftButtonDown({
    param($s, $e)
    $e.Handled = $true
    Remove-List $script:ListCur
    $script:ListCur = $null
    Update-Panel
})

function New-ListChip([string]$text, [bool]$on, $tag, $onClick) {
    $b = New-Object System.Windows.Controls.Border
    $b.CornerRadius = New-Object System.Windows.CornerRadius 9
    $b.Padding      = New-Object System.Windows.Thickness 8, 2, 8, 3
    $b.Margin       = New-Object System.Windows.Thickness 0, 0, 5, 4
    $b.Background   = New-Brush $(if ($on) { '#FF2B3245' } else { '#FF26262C' })
    $b.Cursor       = [System.Windows.Input.Cursors]::Hand
    $b.Tag          = $tag
    $b.Child        = New-PanelText $text 10 $(if ($on) { '#FFF4F4F5' } else { '#FF8B8B94' })
    $b.add_MouseLeftButtonDown($onClick)
    return $b
}

function New-ListRow([string]$list, $it) {
    $row = New-Object System.Windows.Controls.Grid
    $row.Margin = New-Object System.Windows.Thickness 0, 0, 0, 5
    $row.Background = [System.Windows.Media.Brushes]::Transparent
    $row.Cursor = [System.Windows.Input.Cursors]::Hand
    $row.Tag = @{ list = $list; it = $it }
    $c = New-Object System.Windows.Controls.ColumnDefinition; $c.Width = 'Auto'; $row.ColumnDefinitions.Add($c)
    $c = New-Object System.Windows.Controls.ColumnDefinition; $row.ColumnDefinitions.Add($c)
    $c = New-Object System.Windows.Controls.ColumnDefinition; $c.Width = 'Auto'; $row.ColumnDefinitions.Add($c)
    $box = New-PanelText $(if ($it.done) { [char]0xE73A } else { [char]0xE739 }) 11 $(if ($it.done) { '#FF4ADE80' } else { '#FF8B8B94' })
    $box.FontFamily = 'Segoe MDL2 Assets'
    $box.Margin = New-Object System.Windows.Thickness 0, 1, 7, 0
    [void]$row.Children.Add($box)
    $t = New-PanelText $it.text 10.5 $(if ($it.done) { '#FF6B7280' } else { '#FFE4E4E7' })
    if ($it.done) { $t.TextDecorations = [System.Windows.TextDecorations]::Strikethrough }
    [System.Windows.Controls.Grid]::SetColumn($t, 1)
    [void]$row.Children.Add($t)
    # The whole row ticks; the cross removes.
    $row.add_MouseLeftButtonDown({
        param($s, $e)
        $e.Handled = $true
        [void](Set-ListItemDone $s.Tag.list $s.Tag.it.idx (-not $s.Tag.it.done))
        Update-Panel
    })
    $x = New-PanelLink ([string][char]0x2715) '#FF52525B' $row.Tag {
        param($s, $e)
        $e.Handled = $true
        [void](Remove-ListItem $s.Tag.list $s.Tag.it.idx)
        Update-Panel
    }
    $x.FontSize = 9
    $x.Margin = New-Object System.Windows.Thickness 8, 1, 0, 0
    [System.Windows.Controls.Grid]::SetColumn($x, 2)
    [void]$row.Children.Add($x)
    return $row
}

function Update-ListsPage {
    $names = Get-Lists
    if (-not $script:ListCur -or $names -notcontains $script:ListCur) {
        $script:ListCur = $(if ($names.Count) { $names[0] } else { $null })
    }
    $key = (Get-Lang) + '|' + (Get-ListsStamp) + "|$($script:ListCur)|$($script:ListNew)"
    if ($key -eq $script:ListKey) { return }
    $script:ListKey = $key

    $UI.ListTabs.Children.Clear()
    foreach ($n in $names) {
        $open = @((Read-List $n).items | Where-Object { -not $_.done }).Count
        $label = $(if ($open) { "$n  $open" } else { $n })
        [void]$UI.ListTabs.Children.Add((New-ListChip $label ($n -eq $script:ListCur) $n {
            param($s, $e); $e.Handled = $true; $script:ListCur = $s.Tag; $script:ListNew = $false; Update-Panel }))
    }
    [void]$UI.ListTabs.Children.Add((New-ListChip '+' $script:ListNew $null {
        param($s, $e)
        $e.Handled = $true
        $script:ListNew = $true
        $script:ListKey = $null
        Update-Panel
        [void]$UI.ListAdd.Focus()
    }))

    $UI.ListItems.Children.Clear()
    $l = $null
    if ($script:ListCur) { $l = Read-List $script:ListCur }
    if (-not $l -or -not $l.items.Count) {
        $none = New-PanelText (T 'list.empty') 10 '#FF8B8B94'
        $none.Margin = New-Object System.Windows.Thickness 2, 0, 0, 4
        [void]$UI.ListItems.Children.Add($none)
    } else {
        # Still to do on top, ticked off below.
        foreach ($it in @($l.items | Where-Object { -not $_.done }) + @($l.items | Where-Object { $_.done })) {
            [void]$UI.ListItems.Children.Add((New-ListRow $script:ListCur $it))
        }
    }
    $UI.ListAddHint.Text = $(if ($script:ListNew) { T 'list.newHint' } else { T 'list.addHint' })
    $hasDone = $l -and @($l.items | Where-Object { $_.done }).Count
    $UI.ListClear.Text = T 'list.clear'
    $UI.ListClear.Visibility = $(if ($hasDone) { 'Visible' } else { 'Collapsed' })
    # Only an empty list can go - nothing is lost by a stray click.
    $UI.ListDelete.Text = T 'list.delete'
    $UI.ListDelete.Visibility = $(if ($script:ListCur -and $l -and -not $l.items.Count) { 'Visible' } else { 'Collapsed' })
}
