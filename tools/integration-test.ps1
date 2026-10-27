#requires -version 5
<#
  Combined PR regressions on fixed data: translations, cultures, main-limit
  mapping and mascot state transitions. No CLI, network, window or user data.
#>
$ErrorActionPreference = 'Stop'
$Repo = Split-Path -Parent $PSScriptRoot
$script:Cfg = @{ language = 'en'; mainLimit = 'session' }
$script:Checked = 0

function Check([string]$name, [bool]$ok) {
    $script:Checked++
    if (-not $ok) { throw "FAIL: $name" }
}

# Load the production functions without evaluating files that initialize WPF
# or discover the CLI at file scope.
function Read-Function([string]$file, [string]$name) {
    $errors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile(
        (Join-Path $Repo $file), [ref]$null, [ref]$errors)
    if ($errors) { throw "$file has parse errors: $errors" }
    $fn = $ast.Find({ param($a)
        $a -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $a.Name -eq $name
    }, $true)
    if (-not $fn) { throw "Function $name is missing from $file" }
    return [scriptblock]::Create($fn.Extent.Text)
}

. (Join-Path $Repo 'lib\i18n.ps1')
. (Read-Function 'lib\usage.ps1' 'Get-Limits')
. (Read-Function 'lib\usage.ps1' 'Parse-Period')
. (Read-Function 'lib\usage.ps1' 'Parse-ResetStamp')
. (Read-Function 'lib\usage.ps1' 'Collect-UsageProbe')
. (Read-Function 'lib\format.ps1' 'Get-Level')
. (Read-Function 'lib\mascot.ps1' 'Set-MascotMood')

$cultures = @{ en = 'en-US'; ru = 'ru-RU'; fr = 'fr-FR'; 'pt-BR' = 'pt-BR'; es = 'es-ES' }
foreach ($lang in $cultures.Keys) {
    Check "$lang is registered" $Languages.Contains($lang)
    Check "$lang has a translation table" $Strings.ContainsKey($lang)
    $script:Cfg.language = $lang
    Check "$lang culture" ((Get-LangCulture).Name -eq $cultures[$lang])
    foreach ($key in $Strings.en.Keys) {
        Check "$lang has $key" $Strings[$lang].ContainsKey($key)
        $english = @($Strings.en[$key])
        $local = @($Strings[$lang][$key])
        # Russian plural forms intentionally use three entries, while the
        # other languages use two. The new tables must match English arrays.
        if ($lang -in @('pt-BR', 'es')) {
            Check "$lang array length for $key" ($local.Count -eq $english.Count)
        }
        $a = @([regex]::Matches(($english -join ' '), '\{\d+(?:[^}]*)\}') |
            ForEach-Object { $_.Value } | Sort-Object -Unique) -join '|'
        $b = @([regex]::Matches(($local -join ' '), '\{\d+(?:[^}]*)\}') |
            ForEach-Object { $_.Value } | Sort-Object -Unique) -join '|'
        Check "$lang placeholders for $key" ($a -eq $b)
    }
}
'PASS  five language tables, placeholders and cultures'

# The same response as mock-claude.cs, passed through the real asynchronous
# collector after a fake completed process. Freeze only the parser's clock.
$script:FixedNow = [datetime]'2026-10-27T12:00:00'
function Get-Date { return $script:FixedNow }
$script:Samples = New-Object System.Collections.ArrayList
function Add-UsageSample($u) { [void]$script:Samples.Add($u) }
$script:UsageFile = [System.IO.Path]::GetTempFileName()
try {
    $fixture = @'
Current session: 37% resets Oct 28, 7:30am
Current week (all models): 68% resets Oct 31, 6am
Current week (Fable): 12% resets Oct 31, 6am
Last 24h: 24 requests, 3 sessions
  12% of your usage came from subagent-heavy sessions
'@
    [System.IO.File]::WriteAllText($script:UsageFile, $fixture,
        (New-Object System.Text.UTF8Encoding $false))
    $script:Usage = $null
    $script:UsageProc = [pscustomobject]@{ HasExited = $true }
    Collect-UsageProbe
    Check 'completed usage probe is consumed' ($null -eq $script:UsageProc)
    Check 'fixture session percentage' ($script:Usage.session -eq 37)
    Check 'fixture weekly percentage' ($script:Usage.week -eq 68)
    Check 'fixture Fable percentage' ($script:Usage.fable -eq 12)
    Check 'fixture session reset' ($script:Usage.sessionReset -eq [datetime]'2026-10-28T07:30:00')
    Check 'fixture weekly reset' ($script:Usage.weekReset -eq [datetime]'2026-10-31T06:00:00')
    Check 'fixture Fable reset' ($script:Usage.fableReset -eq [datetime]'2026-10-31T06:00:00')
    Check 'fixture daily request/session counts' ($script:Usage.day.requests -eq 24 -and $script:Usage.day.sessions -eq 3)
    Check 'fixture daily stat line' ($script:Usage.day.lines.Count -eq 1 -and
        $script:Usage.day.lines[0] -eq '12% of your usage came from subagent-heavy sessions')
    Check 'absent seven-day stats stay absent' ($null -eq $script:Usage.week7)
    Check 'usage sample is saved once' ($script:Samples.Count -eq 1 -and $script:Samples[0] -eq $script:Usage)
    Check 'usage timestamp records completion' ($script:UsageAt -eq $script:FixedNow)
    Collect-UsageProbe
    Check 'completed response is not processed twice' ($script:Samples.Count -eq 1)
    $singular = Parse-Period "Last 7d: 1 request, 1 session`r`n  one detail`r`n" 'Last 7d'
    Check 'singular seven-day counts parse' ($singular.requests -eq 1 -and $singular.sessions -eq 1 -and
        $singular.lines[0] -eq 'one detail')
    Check 'reset stamp with at and pm' ((Parse-ResetStamp 'Oct 28 at 2:29pm') -eq [datetime]'2026-10-28T14:29:00')
    Check 'invalid reset stamp stays absent' ($null -eq (Parse-ResetStamp 'unknown'))
} finally {
    Remove-Item -LiteralPath $script:UsageFile -Force -ErrorAction SilentlyContinue
    Remove-Item Function:\Get-Date
}
'PASS  mock CLI response, reset stamps and daily/seven-day stats'

$script:Cfg.language = 'unknown'
Check 'unknown language falls back to English' ((Get-Lang) -eq 'en')
$usage = @{ session = 37; week = 82; sessionReset = [datetime]'2026-10-27T18:00:00'
            weekReset = [datetime]'2026-11-01T10:00:00' }
foreach ($mode in @('session', 'week')) {
    $script:Cfg.mainLimit = $mode
    $limits = Get-Limits $usage
    $side = $(if ($mode -eq 'session') { 'week' } else { 'session' })
    Check "$mode main mapping" ($limits.main.key -eq $mode -and $limits.main.pct -eq $usage[$mode])
    Check "$mode main reset" ($limits.main.reset -eq $usage["${mode}Reset"])
    Check "$mode side mapping" ($limits.side.key -eq $side -and $limits.side.pct -eq $usage[$side])
    $empty = Get-Limits $null
    Check "$mode empty data" ($null -eq $empty.main.pct -and $null -eq $empty.side.pct)
    $partial = Get-Limits @{ session = 0 }
    Check "$mode preserves zero session and missing week" (
        $(if ($mode -eq 'session') { $partial.main.pct -eq 0 -and $null -eq $partial.side.pct }
          else { $partial.side.pct -eq 0 -and $null -eq $partial.main.pct }))
}
'PASS  both main-limit modes, resets and missing data'

$script:Acts = @()
function Start-MascotAct([string]$name) { $script:Acts += $name }
$script:Mz = @{ busy = 0; waiting = 0; limit = $null; lastReset = $null
                lastPct = $null; halves = 5; mood = 'sleep'; act = $null }
$script:Cfg.mainLimit = 'session'
Set-MascotMood @() $usage
Check 'initial state does not celebrate' ($script:Acts.Count -eq 0)
$script:Mz.halves = 5
$script:Cfg.mainLimit = 'week'
Set-MascotMood @() $usage
Check 'switching does not celebrate' ($script:Acts.Count -eq 0)
Check 'switching resets heart baseline' ($null -eq $script:Mz.halves)
Check 'weekly state uses weekly percentage' ($script:Mz.pct -eq 82 -and $script:Mz.limit -eq 'week')
$usage.week = 100
Set-MascotMood @() $usage
Check 'exhausted weekly limit makes mascot dead' ($script:Mz.mood -eq 'dead')
$usage.week = 0
$usage.weekReset = $usage.weekReset.AddDays(7)
Set-MascotMood @() $usage
Check 'real weekly reset celebrates once' ($script:Acts.Count -eq 1 -and $script:Acts[0] -eq 'celebrate')
Set-MascotMood @() $usage
Check 'unchanged data does not celebrate again' ($script:Acts.Count -eq 1)
Set-MascotMood @() $null
Check 'missing usage clears percentage' ($null -eq $script:Mz.pct -and -not $script:Mz.crit)
'PASS  switching, heart baseline, exhausted limit and weekly reset'
"all passed ($script:Checked checks)"
