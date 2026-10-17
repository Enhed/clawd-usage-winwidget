<#
  Recurring tasks without Claude: lib/tasks.ps1 with a fake `claude` that answers
  from a list. Run by tools/smoke.ps1 (case "tasks"), or on its own; exit code 0 -
  all passed. Checks:
    - "Run now" while another task runs queues it, and it runs next;
    - an empty answer is retried once on the chat model; empty twice is a failure;
    - finding and removing a task by name touches only that task;
    - fields (tell / message / summary): a quiet run says nothing but leaves its
      summary in the history, which the next run gets.
#>
$ErrorActionPreference = 'Stop'
$Repo = Split-Path -Parent $PSScriptRoot
$script:Root = Join-Path ([System.IO.Path]::GetTempPath()) "clawd-tasks-test-$PID"
$Tasks = Join-Path (Join-Path $script:Root 'home') 'tasks'
[void][System.IO.Directory]::CreateDirectory($Tasks)

# What lib/tasks.ps1 takes from the modules loaded before it.
$script:Cfg = @{ quickModel = 'haiku'; chatModel = 'sonnet'; chatTimeoutSeconds = 300; showTasks = $true
                 tasksMaxPercent = 80; showMascot = $false }
$advWin = [pscustomobject]@{ IsVisible = $true }
$ChatReadOnly = @('Get-Date')
function Get-ClawdHome { Join-Path $script:Root 'home' }
function Load-JsonFile($p) { try { [System.IO.File]::ReadAllText($p) | ConvertFrom-Json } catch { $null } }
function Save-JsonFile($p, $o) { ConvertTo-Json -InputObject $o -Depth 6 | Out-File $p -Encoding utf8 }
function T($k) { $k }
function Get-ChatContext { '<context></context>' }
function Update-Panel {}
function Update-Badge {}
function Save-Chat {}
function Read-ChatReply($x) { @{ text = $x; run = $null; notes = @() } }
$script:Said = @()
function Add-ChatMessage($role, $text) { $script:Said += "$role|$text"; @{} }

. (Join-Path $Repo 'lib\tasks.ps1')

# The fake claude: notes the model and the task, answers the next line of $Answers
# (a hashtable - as the fields of --json-schema).
$script:Started = @()
$script:TaskInput = ''
$script:Answers = New-Object System.Collections.Queue
function Start-Process {
    param($FilePath, $WorkingDirectory, $ArgumentList, $RedirectStandardInput, $RedirectStandardOutput,
          $RedirectStandardError, $WindowStyle, [switch]$PassThru)
    $model = $ArgumentList[[array]::IndexOf($ArgumentList, '--model') + 1]
    $script:Argv = $ArgumentList
    $task  = [regex]::Match([System.IO.File]::ReadAllText($RedirectStandardInput), '<task name="([^"]+)"').Groups[1].Value
    $script:Started += "$model $task"
    $script:TaskInput = [System.IO.File]::ReadAllText($RedirectStandardInput)
    $a = $script:Answers.Dequeue()
    $o = @{ result = $a; is_error = $false; permission_denials = @() }
    if ($a -is [hashtable]) { $o.result = ConvertTo-Json $a -Compress; $o.structured_output = $a }
    $o | ConvertTo-Json -Depth 4 | Out-File $RedirectStandardOutput -Encoding utf8
    [pscustomobject]@{ HasExited = $true; Handle = 1; Id = 0; ExitCode = 0 }
}

$failed = 0
function Check([string]$what, $got, $want) {
    if ("$got" -eq "$want") { Write-Host "  ok    $what" }
    else { Write-Host "  FAIL  $what - got [$got], want [$want]" -ForegroundColor Red; $script:failed++ }
}
function Reset { $script:Started = @(); $script:Said = @(); $script:Answers.Clear() }

try {
    foreach ($n in 'A', 'B') { "---`nevery: 30m`n---`ndo $n" | Out-File (Join-Path $Tasks "$n.md") -Encoding utf8 }

    Write-Host 'find by name'
    Check 'Find-Task A' (Find-Task 'A').name 'A'
    Check 'Find-Task missing' ([bool](Find-Task 'C')) $false

    Write-Host 'queue and retry'
    Reset
    @('', 'A report', 'NOTHING') | ForEach-Object { $script:Answers.Enqueue($_) }
    Request-TaskRun (Find-Task 'A')
    Request-TaskRun (Find-Task 'B')
    Check 'B waits in the queue' ($script:TaskQueue -join ',') 'B'
    Update-Tasks; Update-Tasks; Update-Tasks
    Check 'runs in order' ($script:Started -join '; ') 'haiku A; sonnet A; haiku B'
    Check 'the retry''s report is said' ($script:Said -join '; ') 'clawd|[A] A report'

    Write-Host 'empty twice'
    Reset
    @('', '') | ForEach-Object { $script:Answers.Enqueue($_) }
    Request-TaskRun (Find-Task 'A'); Update-Tasks; Update-Tasks
    Check 'one retry, then stop' ($script:Started -join '; ') 'haiku A; sonnet A'
    Check 'a failure on the task' (Load-TaskState)['A'].error 'task.empty'

    Write-Host 'fields'
    Reset
    $script:Answers.Enqueue(@{ tell = $false; message = ''; summary = 'nothing new, 2 newsletters' })
    $script:Answers.Enqueue(@{ tell = $true; message = 'Bob wrote'; summary = 'mail from Bob' })
    $script:Answers.Enqueue(@{ tell = $false; message = 'ignored'; summary = 'quiet' })
    Request-TaskRun (Find-Task 'B'); Update-Tasks; Update-Tasks
    Check 'a quiet run says nothing' ($script:Said -join '; ') ''
    Request-TaskRun (Find-Task 'B'); Update-Tasks; Update-Tasks
    Check 'the summary goes to the next run' ($script:TaskInput -match 'nothing new, 2 newsletters') $true
    Check 'tell says the message' ($script:Said -join '; ') 'clawd|[B] Bob wrote'
    Request-TaskRun (Find-Task 'B'); Update-Tasks; Update-Tasks
    Check 'the message of a quiet run is dropped' ($script:Said -join '; ') 'clawd|[B] Bob wrote'
    $h = @((Load-TaskState)['B'].history)
    Check 'history: a line per run' (@($h | ForEach-Object { "$($_.text)=$($_.told)" }) -join '; ') 'nothing new, 2 newsletters=False; mail from Bob=True; quiet=False'
    Check 'the schema is passed' ([bool]($script:Argv -contains '--json-schema')) $true

    Write-Host 'remove one'
    [void](Remove-TaskFile 'A')
    Check 'only A is gone' (@(Get-ChildItem $Tasks).Name -join ',') 'B.md'
} catch {
    Write-Host "  FAIL  $($_.Exception.Message) $($_.InvocationInfo.PositionMessage)" -ForegroundColor Red
    $failed++
} finally {
    Remove-Item $script:Root -Recurse -Force -ErrorAction SilentlyContinue
}
if ($failed) { exit 1 }
exit 0
