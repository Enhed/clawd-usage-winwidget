# ----------------------------------------------------------------- panel ----
# Clawd's panel: a small window beside the widget with the tips and the chat
# (the reminders and lists tabs are in panel-pages.ps1).
# Opened and closed by the icon in the header (or its cross), stays open otherwise. The icon tells what
# is waiting: a bell - a reminder went off, a blue chat - Clawd answered, a lamp
# with a number - tips, a grey chat - nothing, just talk.

$panelXaml = [xml](Convert-ThemeXaml (Get-Content -Raw -Encoding UTF8 (Join-Path $script:Root 'panel.xaml')))
$advWin    = [Windows.Markup.XamlReader]::Load((New-Object System.Xml.XmlNodeReader $panelXaml))
Add-ThemeTo $advWin -Pattern
foreach ($n in @('PanelTitle', 'AdvStamp', 'AdvRescan', 'ChatAuto', 'ChatNew', 'AdvClose', 'PanelScroll', 'LblTips', 'AdvList',
                 'ChatList', 'ChatBusy', 'ChatInput', 'ChatHint', 'ChatSend')) {
    $UI[$n] = $advWin.FindName($n)
}
$UI.PanelTitle.Text = "CLAWD  $([char]0x00B7)  v$WidgetVersion"
$script:PanelKey    = $null

$advWin.Content.add_MouseLeftButtonDown({ try { $advWin.DragMove() } catch {} })
$UI.AdvClose.add_MouseLeftButtonDown({ param($s, $e) $e.Handled = $true; $advWin.Hide() })
$UI.AdvRescan.add_MouseLeftButtonDown({
    param($s, $e)
    $e.Handled = $true
    Start-AdvisorScan
    Update-PanelBusy
})
$UI.ChatNew.add_MouseLeftButtonDown({ param($s, $e) $e.Handled = $true; Reset-Chat })
$UI.ChatBusy.Cursor     = [System.Windows.Input.Cursors]::Hand
$UI.ChatBusy.Background = [System.Windows.Media.Brushes]::Transparent
$UI.ChatBusy.add_MouseLeftButtonDown({ param($s, $e) $e.Handled = $true; if (-not $script:RunProc) { Stop-ChatReply } })
# "Auto": Clawd's scripts run without the "Run" click.
$UI.ChatAuto.add_MouseLeftButtonDown({
    param($s, $e)
    $e.Handled = $true
    $script:Cfg.chatAutoRun = -not $script:Cfg.chatAutoRun
    $script:AutoChain = 0
    Save-Config $script:Cfg
    Update-ChatAuto
})

function Update-ChatAuto {
    $on = [bool]$script:Cfg.chatAutoRun
    $UI.ChatAuto.Text       = T 'chat.auto'
    $UI.ChatAuto.Foreground = New-Brush $(if ($on) { '#FF4ADE80' } else { '#FF52525B' })
    $UI.ChatAuto.ToolTip    = $(if ($on) { T 'chat.autoOn' } else { T 'chat.autoOff' })
}

$script:TipRef = $null   # tip being refined: the next message goes with its text

function Submit-ChatInput {
    if ($script:ChatProc) { return }
    $t = $UI.ChatInput.Text.Trim()
    if (-not $t) { return }
    $UI.ChatInput.Text = ''
    if ($script:TipRef) {
        $t = (T 'adv.refineMsg') -f $script:TipRef, $t
        $script:TipRef = $null
    }
    Send-ChatMessage $t
}
$UI.ChatSend.add_MouseLeftButtonDown({ param($s, $e) $e.Handled = $true; Submit-ChatInput })
# Enter sends, Shift+Enter - a new line.
$UI.ChatInput.add_PreviewKeyDown({
    param($s, $e)
    if ($e.Key -ne [System.Windows.Input.Key]::Return) { return }
    $e.Handled = $true
    if ([System.Windows.Input.Keyboard]::Modifiers -band [System.Windows.Input.ModifierKeys]::Shift) {
        $i = $s.CaretIndex
        $s.Text = $s.Text.Insert($i, "`n")
        $s.CaretIndex = $i + 1
    } else {
        Submit-ChatInput
    }
})
$UI.ChatInput.add_TextChanged({
    $UI.ChatHint.Visibility = $(if ($UI.ChatInput.Text) { 'Collapsed' } else { 'Visible' })
})

function New-PanelText([string]$text, [double]$size = 10.5, [string]$color = '#FFD4D4D8') {
    $t = New-Object System.Windows.Controls.TextBlock
    $t.Text         = $text
    $t.FontFamily   = 'Segoe UI'
    $t.FontSize     = $size
    $t.Foreground   = New-Brush $color
    $t.TextWrapping = 'Wrap'
    return $t
}

function New-PanelLink([string]$text, [string]$color, $tag, $onClick) {
    $t = New-PanelText $text 10 $color
    $t.Cursor     = [System.Windows.Input.Cursors]::Hand
    $t.Background = [System.Windows.Media.Brushes]::Transparent
    $t.Margin     = New-Object System.Windows.Thickness 0, 0, 12, 0
    $t.Tag        = $tag
    $t.add_MouseLeftButtonDown($onClick)
    return $t
}

function New-PanelCard([string]$bg, [string]$edge = '#1AFFFFFF') {
    $card = New-Object System.Windows.Controls.Border
    $card.Background      = New-Brush $bg
    $card.CornerRadius    = New-Object System.Windows.CornerRadius 7
    $card.Padding         = New-Object System.Windows.Thickness 9, 6, 9, 7
    $card.Margin          = New-Object System.Windows.Thickness 0, 0, 0, 6
    $card.BorderThickness = New-Object System.Windows.Thickness 1
    $card.BorderBrush     = New-Brush $edge
    return $card
}

function New-TipCard($tip) {
    $edge = $(if ($tip.warn) { $Palette.warn.Wpf } else { '#1AFFFFFF' })
    $card = New-PanelCard '#FF26262C' $edge
    $box = New-Object System.Windows.Controls.StackPanel
    [void]$box.Children.Add((New-PanelText $tip.text))
    if ($tip.act) {
        $open = New-PanelLink ((T $tip.actKey) -f $tip.actArg) '#FF8B8B94' $tip.act {
            param($s, $e)
            $e.Handled = $true
            try { Start-Process $s.Tag } catch {}
        }
        $open.Margin = New-Object System.Windows.Thickness 0, 4, 0, 0
        [void]$box.Children.Add($open)
    }
    $row = New-Object System.Windows.Controls.Grid
    $row.Margin = New-Object System.Windows.Thickness 0, 4, 0, 0
    # Clawd takes it from here: "do it" - he answers with a script to approve,
    # "refine" - the next message goes to him together with the tip.
    if ($script:Cfg.showChat) {
        $acts = New-Object System.Windows.Controls.StackPanel
        $acts.Orientation = 'Horizontal'
        [void]$acts.Children.Add((New-PanelLink (T 'adv.do') '#FF4ADE80' $tip {
            param($s, $e)
            $e.Handled = $true
            Send-ChatMessage ((T 'adv.doMsg') -f $s.Tag.text)
        }))
        [void]$acts.Children.Add((New-PanelLink (T 'chat.refine') '#FF60A5FA' $tip {
            param($s, $e)
            $e.Handled = $true
            $script:TipRef = $s.Tag.text
            $UI.ChatInput.Text = ''
            $UI.ChatHint.Text = T 'adv.refineHint'
            [void]$UI.ChatInput.Focus()
        }))
        [void]$row.Children.Add($acts)
    }
    $x = New-PanelLink (T 'adv.close') '#FF6B7280' $tip {
        param($s, $e)
        $e.Handled = $true
        Close-AdvisorTip $s.Tag
    }
    $x.HorizontalAlignment = 'Right'
    $x.Margin = New-Object System.Windows.Thickness 0
    [void]$row.Children.Add($x)
    [void]$box.Children.Add($row)
    $card.Child = $box
    return $card
}

# A script Clawd proposes: the code as is, and what to do with it.
function New-RunBlock($msg) {
    $box = New-Object System.Windows.Controls.StackPanel
    $code = New-Object System.Windows.Controls.TextBox
    $code.Text            = $msg.run.script
    $code.IsReadOnly      = $true
    $code.FontFamily      = 'Consolas'
    $code.FontSize        = 9.5
    $code.Foreground      = New-Brush '#FFB4B4BC'
    $code.Background      = New-Brush '#FF141416'
    $code.BorderThickness = New-Object System.Windows.Thickness 0
    $code.Padding         = New-Object System.Windows.Thickness 5, 4, 5, 4
    $code.Margin          = New-Object System.Windows.Thickness 0, 5, 0, 5
    $code.TextWrapping    = 'Wrap'
    $code.MaxHeight       = 120
    $code.VerticalScrollBarVisibility = 'Hidden'
    [void]$box.Children.Add($code)

    $row = New-Object System.Windows.Controls.StackPanel
    $row.Orientation = 'Horizontal'
    switch ($msg.run.state) {
        'pending' {
            [void]$row.Children.Add((New-PanelLink (T 'chat.run') '#FF4ADE80' $msg {
                param($s, $e); $e.Handled = $true; Start-ChatRun $s.Tag }))
            [void]$row.Children.Add((New-PanelLink (T 'chat.refine') '#FF60A5FA' $msg {
                param($s, $e)
                $e.Handled = $true
                $UI.ChatHint.Text = T 'chat.refineHint'
                [void]$UI.ChatInput.Focus()
            }))
            [void]$row.Children.Add((New-PanelLink (T 'chat.skip') '#FF6B7280' $msg {
                param($s, $e); $e.Handled = $true; Set-RunState $s.Tag 'skipped' }))
        }
        'running'  { [void]$row.Children.Add((New-PanelText (T 'chat.state.running') 10 $Palette.warn.Wpf)) }
        'done' {
            $ok = ($msg.run.code -eq 0)
            [void]$row.Children.Add((New-PanelText ((T 'chat.state.done') -f $msg.run.code) 10 $(if ($ok) { $Palette.ok.Wpf } else { $Palette.crit.Wpf })))
        }
        default    { [void]$row.Children.Add((New-PanelText (T "chat.state.$($msg.run.state)") 10 '#FF6B7280')) }
    }
    [void]$box.Children.Add($row)
    return $box
}

# Tool calls Clawd was refused and asks the user to approve: the tool and its
# arguments as they are, Run / Not now.
function New-ActBlock($msg) {
    $box = New-Object System.Windows.Controls.StackPanel
    [void]$box.Children.Add((New-PanelText (T 'chat.actHead') 9.5 '#FF8B8B94'))
    $code = New-Object System.Windows.Controls.TextBox
    $code.Text            = (@($msg.act.calls | ForEach-Object { "$($_.tool -replace '^mcp__', '') $($_.input)" }) -join "`n")
    $code.IsReadOnly      = $true
    $code.FontFamily      = 'Consolas'
    $code.FontSize        = 9.5
    $code.Foreground      = New-Brush '#FFB4B4BC'
    $code.Background      = New-Brush '#FF141416'
    $code.BorderThickness = New-Object System.Windows.Thickness 0
    $code.Padding         = New-Object System.Windows.Thickness 5, 4, 5, 4
    $code.Margin          = New-Object System.Windows.Thickness 0, 3, 0, 5
    $code.TextWrapping    = 'Wrap'
    $code.MaxHeight       = 120
    $code.VerticalScrollBarVisibility = 'Hidden'
    [void]$box.Children.Add($code)
    $row = New-Object System.Windows.Controls.StackPanel
    $row.Orientation = 'Horizontal'
    if ($msg.act.state -eq 'pending') {
        [void]$row.Children.Add((New-PanelLink (T 'chat.run') '#FF4ADE80' $msg {
            param($s, $e); $e.Handled = $true; Approve-ChatAct $s.Tag }))
        [void]$row.Children.Add((New-PanelLink (T 'chat.skip') '#FF6B7280' $msg {
            param($s, $e); $e.Handled = $true; Set-ActState $s.Tag 'skipped' }))
    } else {
        [void]$row.Children.Add((New-PanelText (T "chat.act.$($msg.act.state)") 10 '#FF6B7280'))
    }
    [void]$box.Children.Add($row)
    return $box
}

# A task was refused permissions it cannot ask for in the background: the rules
# as they would go to its `tools`, Allow / Not now.
function New-GrantBlock($msg) {
    $box = New-Object System.Windows.Controls.StackPanel
    [void]$box.Children.Add((New-PanelText ((T 'task.grantHead') -f $msg.grant.task) 9.5 '#FF8B8B94'))
    $code = New-Object System.Windows.Controls.TextBox
    $code.Text            = ($msg.grant.rules -join "`n")
    $code.IsReadOnly      = $true
    $code.FontFamily      = 'Consolas'
    $code.FontSize        = 9.5
    $code.Foreground      = New-Brush '#FFB4B4BC'
    $code.Background      = New-Brush '#FF141416'
    $code.BorderThickness = New-Object System.Windows.Thickness 0
    $code.Padding         = New-Object System.Windows.Thickness 5, 4, 5, 4
    $code.Margin          = New-Object System.Windows.Thickness 0, 3, 0, 5
    $code.TextWrapping    = 'Wrap'
    [void]$box.Children.Add($code)
    $row = New-Object System.Windows.Controls.StackPanel
    $row.Orientation = 'Horizontal'
    if ($msg.grant.state -eq 'pending') {
        [void]$row.Children.Add((New-PanelLink (T 'task.grant') '#FF4ADE80' $msg {
            param($s, $e); $e.Handled = $true; Grant-TaskRules $s.Tag }))
        [void]$row.Children.Add((New-PanelLink (T 'chat.skip') '#FF6B7280' $msg {
            param($s, $e); $e.Handled = $true; Set-TaskGrantState $s.Tag 'skipped' }))
    } else {
        [void]$row.Children.Add((New-PanelText (T "task.grant.$($msg.grant.state)") 10 '#FF6B7280'))
    }
    [void]$box.Children.Add($row)
    return $box
}

# Messages from the phone carry a small mark: they were not written here.
function New-RemoteBox($msg, [string]$color) {
    $box = New-Object System.Windows.Controls.StackPanel
    $tag = New-PanelText "$([char]0xE8EA)" 8.5 '#FF6B7280'
    $tag.FontFamily = 'Segoe MDL2 Assets'
    $row = New-Object System.Windows.Controls.StackPanel
    $row.Orientation = 'Horizontal'
    $row.Margin = New-Object System.Windows.Thickness 0, 0, 0, 2
    [void]$row.Children.Add($tag)
    $cap = New-PanelText "  $(T 'chat.remoteTag')  $($msg.at.ToString('HH:mm'))" 8.5 '#FF6B7280'
    [void]$row.Children.Add($cap)
    [void]$box.Children.Add($row)
    [void]$box.Children.Add((New-PanelText $msg.text 10.5 $color))
    return $box
}

# Right-click on a message: Copy, the text as it is.
function Add-CopyMenu($el, [string]$text) {
    if (-not $text) { return $el }
    $mi = New-Object System.Windows.Controls.MenuItem
    $mi.Header = T 'chat.copy'
    $mi.Tag    = $text
    $mi.add_Click({ param($s, $e); try { [System.Windows.Clipboard]::SetText($s.Tag) } catch {} })
    $cm = New-Object System.Windows.Controls.ContextMenu
    [void]$cm.Items.Add($mi)
    $el.ContextMenu = $cm
    return $el
}

function New-ChatItem($msg) {
    $text = @(@($msg.text) + $(if ($msg.run) { $msg.run.script }) | Where-Object { $_ }) -join "`n`n"
    return Add-CopyMenu (New-ChatCard $msg) $text
}

function New-ChatCard($msg) {
    switch ($msg.role) {
        'user' {
            $card = New-PanelCard '#FF2B3245'
            $card.HorizontalAlignment = 'Right'
            $card.Margin = New-Object System.Windows.Thickness 36, 0, 0, 6
            $card.Child = $(if ($msg.remote) { New-RemoteBox $msg '#FFD4D4D8' } else { New-PanelText $msg.text })
            return $card
        }
        'remind' {
            $card = New-PanelCard '#FF26262C' '#FFD77757'
            $card.Child = New-PanelText "$([char]0x23F0) $($msg.text)" 10.5 '#FFF4F4F5'
            return $card
        }
        'note' {
            $t = New-PanelText $msg.text 9.5 '#FF8B8B94'
            $t.Margin = New-Object System.Windows.Thickness 4, 0, 4, 6
            return $t
        }
        default {
            $card = New-PanelCard '#FF26262C'
            $card.Margin = New-Object System.Windows.Thickness 0, 0, 24, 6
            if ($msg.remote) { $card.Child = New-RemoteBox $msg '#FFD4D4D8'; return $card }
            $box = New-Object System.Windows.Controls.StackPanel
            if ($msg.text) { [void]$box.Children.Add((New-PanelText $msg.text)) }
            if ($msg.run) { [void]$box.Children.Add((New-RunBlock $msg)) }
            if ($msg.act) { [void]$box.Children.Add((New-ActBlock $msg)) }
            if ($msg.grant) { [void]$box.Children.Add((New-GrantBlock $msg)) }
            $card.Child = $box
            return $card
        }
    }
}

# "Thinking..." / "running the script" under the conversation, the check time in the header.
function Update-PanelBusy {
    $dots = '.' * (1 + [int]((Get-Date).Millisecond / 334))
    if ($script:RunProc) {
        $UI.ChatBusy.Text = (T 'chat.running') + $dots
    } elseif ($script:ChatProc) {
        $sec = [int]([datetime]::Now - $script:ChatProc.at).TotalSeconds
        $UI.ChatBusy.Text = (T 'chat.thinking') + $dots + $(if ($sec -ge 10) { "  $((T 'chat.sec') -f $sec)" } else { '' })
    }
    $UI.ChatBusy.Visibility = $(if ($script:RunProc -or $script:ChatProc) { 'Visible' } else { 'Collapsed' })
    $UI.ChatSend.Opacity = $(if ($script:ChatProc) { 0.35 } else { 1.0 })
    $UI.AdvStamp.Text = $(if ($script:AdvJob) { T 'adv.checking' }
                          elseif ($script:AdvAt) { (T 'adv.checked') -f $script:AdvAt.ToString('HH:mm') }
                          else { '' })
}

# The open tab is brought up to date; the others wait until they are opened.
function Update-Panel([switch]$Force) {
    Update-PanelBusy
    Update-PanelTabs
    switch ($script:PanelTab) {
        'remind' { Update-RemindPage }
        'lists'  { Update-ListsPage }
        default  { Update-ChatPage -Force:$Force }
    }
}

# Rebuilt only when something changed - a tick must not reset hover and scroll.
function Update-ChatPage([switch]$Force) {
    $UI.AdvRescan.ToolTip = T 'adv.rescan'
    $UI.ChatNew.ToolTip   = T 'chat.new'
    $UI.ChatBusy.ToolTip  = T 'chat.stop'
    Update-ChatAuto
    if ($script:TipRef)                  { $UI.ChatHint.Text = T 'adv.refineHint' }
    elseif (-not $UI.ChatInput.IsFocused) { $UI.ChatHint.Text = T 'chat.hint' }
    $tips = @(Get-AdvisorTips)
    # The panel's own messages and the phone conversation, in order of time.
    $i = 0
    $feed = @(@($script:Chat.messages) + @($script:Remote.items) |
              ForEach-Object { @{ m = $_; n = $i++ } } |
              Sort-Object { $_.m.at }, { $_.n } | ForEach-Object { $_.m })
    $key = (Get-Lang) + '|' + (@($tips | ForEach-Object { "$($_.sig)=$($_.text)" }) -join "`n") + '|' +
           (@($feed | ForEach-Object { "$($_.role):$($_.text.Length):$(if ($_.run) { $_.run.state }):$(if ($_.act) { $_.act.state }):$(if ($_.grant) { $_.grant.state })" }) -join ',')
    if (-not $Force -and $key -eq $script:PanelKey) { return }
    $script:PanelKey = $key

    $UI.LblTips.Text       = T 'adv.tips'
    $UI.LblTips.Visibility = $(if ($tips.Count) { 'Visible' } else { 'Collapsed' })
    $UI.AdvList.Children.Clear()
    foreach ($tip in $tips) { [void]$UI.AdvList.Children.Add((New-TipCard $tip)) }

    $UI.ChatList.Children.Clear()
    if ($tips.Count -and $feed.Count) {
        $sep = New-Object System.Windows.Controls.Border
        $sep.Background = New-Brush '#1AFFFFFF'
        $sep.Height = 1
        $sep.Margin = New-Object System.Windows.Thickness 0, 4, 0, 10
        [void]$UI.ChatList.Children.Add($sep)
    }
    if (-not $feed.Count) {
        [void]$UI.ChatList.Children.Add((New-ChatItem @{ role = 'note'; text = T 'chat.hello' }))
    }
    foreach ($m in $feed) { [void]$UI.ChatList.Children.Add((New-ChatItem $m)) }
    if ($advWin.IsVisible) {
        $UI.PanelScroll.UpdateLayout()
        $UI.PanelScroll.ScrollToEnd()
    }
}

function Show-Panel {
    if ($advWin.IsVisible) { $advWin.Hide(); return }
    $script:ChatUnread = $false
    $script:RemindDue  = @()
    $advWin.Content.LayoutTransform = $win.Content.LayoutTransform
    # Above other windows only together with the widget itself (topmost).
    $advWin.Topmost = $win.Topmost
    $advWin.Show()
    Update-Panel -Force
    $advWin.UpdateLayout()
    # Beside the widget: to the left if there is room, otherwise to the right.
    # The panel border sits inside an 8-unit margin (room for the shadow).
    $pad  = 8 * [double]$script:Cfg.scale
    $area = [System.Windows.SystemParameters]::VirtualScreenLeft
    $left = $win.Left - $advWin.ActualWidth + $pad - 6
    if ($left -lt $area) { $left = $win.Left + $win.ActualWidth - $pad + 6 }
    $advWin.Left = $left
    $advWin.Top  = $win.Top - $pad
    $advWin.Activate()
    [void]$UI.ChatInput.Focus()
    Update-Badge
}

function Update-Badge {
    $tips = @(Get-AdvisorTips)
    $glyph = [char]0xE8F2; $count = ''; $color = '#FF6B7280'; $tip = T 'chat.badge'
    if ($script:RemindDue.Count) {
        $glyph = [char]0xEA8F; $count = "$($script:RemindDue.Count)"; $color = '#FFD77757'; $tip = T 'chat.badgeRemind'
    } elseif ($script:ChatUnread) {
        $color = '#FF60A5FA'; $tip = T 'chat.badgeUnread'
    } elseif ($tips.Count) {
        $glyph = [char]0xE82F; $count = "$($tips.Count)"; $tip = (T 'adv.badge') -f $tips.Count
        $color = $(if (@($tips | Where-Object { $_.warn }).Count) { $Palette.warn.Wpf } else { '#FF8B8B94' })
    }
    $UI.TipIcon.Text  = $glyph
    $UI.TipCount.Text = $count
    $UI.TipCount.Visibility = $(if ($count) { 'Visible' } else { 'Collapsed' })
    $UI.TipBadge.SetValue([System.Windows.Documents.TextElement]::ForegroundProperty, (New-Brush $color))
    $UI.TipBadge.ToolTip = $tip
    $show = $script:Cfg.showChat -or $tips.Count -or $script:RemindDue.Count
    $UI.TipBadge.Visibility = $(if ($show) { 'Visible' } else { 'Collapsed' })
}
