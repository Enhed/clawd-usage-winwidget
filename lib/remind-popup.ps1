# ---------------------------------------------------------- remind popup ----
# A reminder that went off shows as a card in the bottom-right corner, above the
# tray, like a phone notification: put it off (+15m, +1h, +3h, tomorrow 9:00, or
# any time in the Reminders tab) or mark it done. It stays until answered - the
# user may be away; several stack up. Putting off makes the file a reminder again.

$PopupXaml = Convert-ThemeXaml (Get-Content -Raw -Encoding UTF8 (Join-Path $script:Root 'remind-popup.xaml'))
$script:Popups = New-Object System.Collections.ArrayList

# Stacked from the bottom of the work area up, newest at the bottom.
function Update-PopupPlaces {
    $area = [System.Windows.SystemParameters]::WorkArea
    $y = $area.Bottom - 4
    for ($i = $script:Popups.Count - 1; $i -ge 0; $i--) {
        $w = $script:Popups[$i].win
        $y -= $w.ActualHeight
        $w.Left = $area.Right - $w.ActualWidth - 4
        $w.Top  = [math]::Max($area.Top, $y)
    }
}

function Close-RemindPopup($p) {
    try { $p.win.Close() } catch {}
    [void]$script:Popups.Remove($p)
    $script:RemindDue = @($script:RemindDue | Where-Object { $_.path -ne $p.r.path })
    Update-PopupPlaces
    Update-Badge
}

# Put off: the reminder file again, for the new time; the fired copy goes.
function Set-PopupLater($p, [string]$when) {
    $at = ConvertFrom-RemindWhen $when
    if (-not $at) { return }
    [void](New-ReminderFile $at $p.r.text)
    if ($p.done) { try { Remove-Item -LiteralPath $p.done -Force } catch {} }
    [void](Add-ChatMessage 'note' ((T 'pop.later') -f (Format-RemindTime $at), $p.r.text))
    Close-RemindPopup $p
    Update-Panel
}

function Show-RemindPopup($r, [string]$donePath, [string]$text) {
    $w = [Windows.Markup.XamlReader]::Parse($PopupXaml)
    Add-ThemeTo $w
    $p = @{ win = $w; r = $r; done = $donePath }
    $w.Content.LayoutTransform = $win.Content.LayoutTransform
    $w.FindName('PopTitle').Text = T 'chat.remindTitle'
    $w.FindName('PopTime').Text  = Format-RemindTime $r.at
    $w.FindName('PopText').Text  = $text
    $w.FindName('PopLater').Text = T 'pop.laterHead'
    $snooze = $w.FindName('PopSnooze')
    foreach ($c in @(T 'pop.snooze')) {
        $chip = New-ListChip $c $false @{ p = $p; when = $c } {
            param($s, $e); $e.Handled = $true; Set-PopupLater $s.Tag.p $s.Tag.when }
        [void]$snooze.Children.Add($chip)
    }
    # Any other time: the Reminders tab with the text in the form.
    [void]$snooze.Children.Add((New-ListChip ([string][char]0x2026) $false $p {
        param($s, $e)
        $e.Handled = $true
        $pp = $s.Tag
        if ($pp.done) { try { Remove-Item -LiteralPath $pp.done -Force } catch {} }
        Close-RemindPopup $pp
        if (-not $advWin.IsVisible) { Show-Panel }
        Set-PanelTab 'remind'
        $UI.RemText.Text = $pp.r.text
        [void]$UI.RemWhen.Focus()
    }))
    $done = $w.FindName('PopDone')
    $done.Text = T 'pop.done'
    $done.Tag = $p
    $done.add_MouseLeftButtonDown({ param($s, $e) $e.Handled = $true; Close-RemindPopup $s.Tag })
    $w.Content.add_MouseLeftButtonDown({ try { $w.DragMove() } catch {} }.GetNewClosure())
    [void]$script:Popups.Add($p)
    $w.Show()
    $w.UpdateLayout()
    Update-PopupPlaces
    try { [System.Media.SystemSounds]::Asterisk.Play() } catch {}
}
