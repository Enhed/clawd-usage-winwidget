#requires -version 5
<#
  Reminder parser regressions without Claude, WPF or user files.
  powershell -NoProfile -ExecutionPolicy Bypass -File tools\reminders-test.ps1
#>
$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
$errors = $null
$ast = [System.Management.Automation.Language.Parser]::ParseFile(
    (Join-Path $repo 'lib\reminders.ps1'), [ref]$null, [ref]$errors)
if ($errors) { throw ($errors -join "`n") }
foreach ($name in @('Read-RemindOffset', 'ConvertFrom-RemindWhen')) {
    $fn = $ast.Find({ param($node)
        $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq $name
    }, $true)
    if (-not $fn) { throw "Function not found: $name" }
    . ([scriptblock]::Create($fn.Extent.Text))
}

# Fix the clock so weekday and relative-time checks do not depend on the run date.
$script:Now = [datetime]'2026-10-27T16:00:00'
$script:TestCulture = 'en-US'
function Get-Date {
    param([int]$Year, [int]$Month, [int]$Day)
    if ($PSBoundParameters.Count) { return [datetime]::new($Year, $Month, $Day, 16, 0, 0) }
    return $script:Now
}
function Get-LangCulture { [System.Globalization.CultureInfo]::GetCultureInfo($script:TestCulture) }
$script:Count = 0
$script:Failed = 0
function Check([string]$inputText, $want) {
    $script:Count++
    $at = ConvertFrom-RemindWhen $inputText
    $got = $(if ($null -ne $at) { $at.ToString('yyyy-MM-dd HH:mm') } else { '<fallback>' })
    $expected = $(if ($null -ne $want) { [string]$want } else { '<fallback>' })
    if ($got -ne $expected) {
        Write-Host "FAIL [$inputText] got [$got], want [$expected]"
        $script:Failed++
    }
}

# An unknown phrase must reach the model fallback, not become a weekday.
foreach ($text in @('quinze minutes', 'quinze dias', 'dans quinze minutes', 'em quinze minutos',
    'daqui a quinze minutos', 'quarter hour', 'money', 'sunday evening', 'sexta depois do almoço', '3/4')) {
    Check $text $null
}
foreach ($case in @(
    @('tomorrow 10:00', '2026-10-28 10:00'),
    @('in 2 hours', '2026-10-27 18:00'),
    @('через неделю 15:00', '2026-11-03 15:00'),
    @('demain 18h30', '2026-10-28 18:30'),
    @('dans une semaine', '2026-11-03 10:00'),
    @('amanhã às 10', '2026-10-28 10:00'),
    @('depois de amanhã', '2026-10-29 10:00'),
    @('daqui a 20 min', '2026-10-27 16:20'),
    @('daqui a uma hora', '2026-10-27 17:00'),
    @('daqui a meia hora', '2026-10-27 16:30'),
    @('em 2 meses', '2026-12-27 10:00'),
    @('25.12 14:00', '2026-12-25 14:00'),
    @('2026-12-25 14:00', '2026-12-25 14:00')
)) { Check $case[0] $case[1] }

# Full names, common abbreviations and inflected Russian names remain supported.
$weekdays = @(
    @('mon', 1), @('on Monday', 1), @('tuesday', 2), @('wednesday', 3), @('thursday', 4),
    @('friday', 5), @('saturday', 6), @('sun.', 0), @('Sunday', 0),
    @('пн', 1), @('в понедельник', 1), @('во вторник', 2), @('в среду', 3), @('четверг', 4),
    @('в пятницу', 5), @('субботу', 6), @('воскресенье', 0),
    @('lun', 1), @('le lundi', 1), @('mardi', 2), @('mercredi', 3), @('jeudi', 4),
    @('vendredi', 5), @('samedi', 6), @('dimanche', 0),
    @('seg', 1), @('segunda-feira', 1), @('terça-feira', 2), @('terca-feira', 2),
    @('próxima quarta', 3), @('qui', 4), @('quinta-feira', 4), @('na sexta', 5),
    @('sexta-feira', 5), @('sábado', 6), @('sabado', 6), @('domingo', 0)
)
foreach ($case in $weekdays) {
    $delta = ([int]$case[1] - [int]$script:Now.DayOfWeek + 7) % 7
    $want = $script:Now.Date.AddDays($delta).AddHours(10)
    if ($want -le $script:Now) { $want = $want.AddDays(7) }
    Check $case[0] $want.ToString('yyyy-MM-dd HH:mm')
}
foreach ($culture in @('ru-RU', 'fr-FR', 'pt-BR')) {
    $script:TestCulture = $culture
    Check '25/12 14:00' '2026-12-25 14:00'
}
if ($script:Failed) { throw "$script:Failed of $script:Count reminder parser checks failed" }
Write-Host "PASS $script:Count reminder parser checks"