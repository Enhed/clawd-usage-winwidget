# ------------------------------------------------------------- account ----
# `claude auth status` returns JSON: logged in or not, email, subscription type.

$script:AuthProc = $null
$script:AuthFile = Join-Path $env:TEMP "cuw-auth-$PID.txt"
$script:AuthTry  = [datetime]::MinValue
$script:Account  = $null   # @{ loggedIn; plan; email }

$PlanNames = @{ max = 'Max'; pro = 'Pro'; team = 'Team'; enterprise = 'Enterprise'; free = 'Free' }

function Start-AuthProbe {
    if ($script:AuthProc -and -not $script:AuthProc.HasExited) { return }
    $script:AuthTry = Get-Date
    try {
        $script:AuthProc = Start-Process -FilePath $script:ClaudeExe `
            -ArgumentList 'auth','status' `
            -RedirectStandardOutput $script:AuthFile -NoNewWindow -PassThru
    } catch {
        $script:AuthProc = $null
    }
}

function Collect-AuthProbe {
    if (-not $script:AuthProc -or -not $script:AuthProc.HasExited) { return }
    $script:AuthProc = $null
    try {
        $j = [System.IO.File]::ReadAllText($script:AuthFile, [System.Text.Encoding]::UTF8) | ConvertFrom-Json
    } catch { return }
    $plan = [string]$j.subscriptionType
    if ($PlanNames.ContainsKey($plan)) { $plan = $PlanNames[$plan] }
    elseif (-not $plan -and $j.authMethod -and $j.authMethod -ne 'claude.ai') { $plan = 'API' }
    $script:Account = @{ loggedIn = [bool]$j.loggedIn; plan = $plan; email = [string]$j.email }
}
