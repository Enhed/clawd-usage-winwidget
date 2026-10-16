# clawd-usage-winwidget

A tiny floating window + tray icon for Windows that shows how much of your Claude
plan limits you've used — the same numbers as `/usage` in Claude Code, refreshed
every minute. And a pixel Clawd who lives in it and reacts to what your sessions
are doing.

![A session starts working, finishes, then waits for you](docs/tour.gif)

**English** · [Русский](README.ru.md)

- **Official numbers only.** Percentages come from `claude -p "/usage"` — the
  slash command runs headless, talks to Anthropic with your existing login and
  **does not call the model or spend tokens**.
- **No dependencies.** Plain Windows PowerShell 5.1 + WPF, which ship with
  Windows. No Node, no npm, no installer. You only need Claude Code itself.
- **Clawd.** The crab from Claude Code's welcome screen, built from the same block
  glyphs and with the same animations. He sleeps when nothing runs, runs around
  when a session works, waves when a session is waiting for you, sweats near the
  limit and lies belly-up when it's used up.

<img src="docs/preview.png" alt="Widget with details expanded" width="354">

## Install

Requirements: Windows 10/11 and [Claude Code](https://docs.claude.com/en/docs/claude-code)
installed and logged in (`claude` on `PATH`).

```powershell
git clone https://github.com/Enhed/clawd-usage-winwidget.git
```

or download the ZIP and unpack it anywhere. Then double-click `start-widget.vbs`
(it starts the widget silently, without a console window).

Start with Windows — run once in PowerShell from the widget folder:

```powershell
$a = New-ScheduledTaskAction -Execute "wscript.exe" -Argument "`"$PWD\start-widget.vbs`""
$t = New-ScheduledTaskTrigger -AtLogOn
Register-ScheduledTask -TaskName "clawd usage widget" -Action $a -Trigger $t -RunLevel Limited
```

Only one copy runs at a time, so a manual start next to autostart is harmless.

Windows hides new tray icons in the overflow (`^`). To keep it visible:
Settings → Personalization → Taskbar → Other system tray icons → `clawd-usage-winwidget`.

## What it shows

- **Big number** — current session (the 5-hour window), straight from the server.
  The bar goes green → yellow (60%) → red (85%).
- **resets in 3h 03m** — time until the window resets, from the exact reset time
  in `/usage`.
- **WEEK** — weekly limit and time to reset. **FABLE · WEEK** — the separate
  weekly Fable limit; hidden if `/usage` doesn't report it.
- **SESSIONS** — how many Claude Code sessions are running, how many are
  working and how many are waiting for you. Hover for the list: `▶` working,
  `?` waiting (permission, question, dialog — what exactly is in brackets),
  `○` idle, plus the folder. Handy for catching a forgotten agent quietly
  burning your limit.
- **Service status** — green "All Claude systems operational", or yellow/red
  with the active incident and affected components. Click opens
  status.claude.com.
- **Tray icon** — the same percentage as a colored number; the tooltip adds the
  week and Fable.
- Bottom line — your plan and account email (red "not logged in" if auth
  expired) and the time of the last `/usage` answer, marked "stale" if it's old.

The ▾ in the header expands details (remembered between runs):

- **LAST 24 HOURS / LAST 7 DAYS** — requests, sessions and the "What's
  contributing to your limits usage?" breakdown from `/usage`: share on large
  context, always-on context, subagent-heavy sessions, top MCP servers, skills
  and subagents. Claude Code itself calls this approximate and counts only this
  computer.
- **Version** — your Claude Code version. If a newer one is out the line turns
  yellow: hover for the official CHANGELOG between your version and the latest,
  click to run `claude update` in a separate window.

Left-click the tray icon to show/hide the window; right-click for the menu:
refresh, larger/smaller, language, open config, exit. Drag the window anywhere —
the position is saved.

### Clawd

<table>
<tr>
<td align="center"><img src="docs/sleep.gif" width="380" alt="No Claude Code running — burrows into the sand and sleeps"><br><sub>No Claude Code running — burrows into the sand and sleeps</sub></td>
<td align="center"><img src="docs/clicks.gif" width="380" alt="Click him — a random Claude Code animation and a heart"><br><sub>Click him — a random Claude Code animation and a heart</sub></td>
</tr>
<tr>
<td align="center"><img src="docs/limit.gif" width="380" alt="Session limit used up — belly-up; click and his soul floats out"><br><sub>Session limit used up — belly-up; click and his soul floats out</sub></td>
<td align="center"><img src="docs/reset.gif" width="380" alt="The 5-hour window resets — celebration and confetti"><br><sub>The 5-hour window resets — celebration and confetti</sub></td>
</tr>
<tr>
<td align="center"><img src="docs/hearts.gif" width="380" alt="Hearts are his health — the session limit left"><br><sub>Hearts are his health — the session limit left</sub></td>
<td align="center"><img src="docs/weather.gif" width="380" alt="The sky follows real time of day and live weather"><br><sub>The sky follows real time of day and live weather</sub></td>
</tr>
</table>

| situation | Clawd |
|---|---|
| Claude Code isn't running | burrows into the sand and sleeps, "z"s float up |
| sessions are idle | wanders, looks around, follows your cursor, whistles; sometimes waves or stretches |
| 10 minutes with no mouse over the window | dozes standing up, sometimes startles |
| a session is working | runs edge to edge with a focused squint, dust flying |
| a session is waiting for you | wide eyes, jumps and waves, yellow "?" above |
| a session just finished | crouches and throws his arms up, like in Claude Code |
| you click him | a random Claude Code animation — jump, spin, peekaboo, wink, boop, sneeze, coin hop… — and a heart |
| the 5-hour window resets | celebrates: two jumps, green "!", confetti |
| session above the red threshold | sweats and darts his eyes |
| session at 100% | lies belly-up with X eyes; click him and his soul floats out on a string, anime-style |

The three hearts in the header are his health, tamagotchi-style: how much of the
session limit is left. Each half-heart is about 16.7%; zero hearts only at 100%.
Health changes how he behaves on top of everything above — full of energy he
walks faster and hops, tired he yawns and slows down, barely alive he staggers,
sweats and sometimes trips over.

Right-click Clawd for developer mode: force any state, play any animation, set
the hearts, pick time of day and weather, or play everything as a demo.
"Auto" goes back to live data.

### Sky

Behind the numbers there's a faint sky that fades into the window edges. It
follows real sunrise and sunset for your location: the sun moves along an arc,
at night there's the moon in its actual phase and twinkling stars. Weather adds
clouds drifting with the wind, drizzle, rain, showers, snow (that settles under
Clawd's feet), fog and thunderstorms. Hover for city, temperature, weather, wind,
sunrise and sunset.

Weather comes from [Open-Meteo](https://open-meteo.com), falling back to
[met.no](https://api.met.no) where Open-Meteo is blocked; both need no key.
Location is looked up once per run by IP via [ipwho.is](https://ipwho.is) — set
`weatherLat` / `weatherLon` to skip that. Without network the sky still follows
the clock. Turn it off with `showSky`.

## Where the data comes from

| what | source | how often |
|---|---|---|
| limits and stats | `claude -p "/usage" --output-format text` | every 60 s |
| sessions | `~/.claude/sessions/<pid>.json`, kept by Claude Code itself; only live processes count | every tick |
| account | `claude auth status` | every 10 min |
| latest version | `downloads.claude.ai/claude-code-releases/latest` (or `stable` if `autoUpdatesChannel` says so) — the same URL the official installer uses | hourly |
| changelog | `raw.githubusercontent.com/anthropics/claude-code/main/CHANGELOG.md` | only when an update is available |
| status | `status.claude.com/api/v2/summary.json` | every 2 min |
| weather | Open-Meteo / met.no, location via ipwho.is | every 15 min |

`/usage` takes about two seconds, so it runs asynchronously and the window never
freezes. If it doesn't answer, the widget keeps the last numbers and marks them
stale.

> Don't run `claude -p "/usage"` by hand from Git Bash: MSYS rewrites `/usage`
> into a path (`C:/Program Files/Git/usage`) and the prompt goes to the model,
> spending tokens. PowerShell and cmd are fine.

## config.json

Created next to the script on first save; open it from the tray menu. Changes
are picked up on the fly, no restart needed.

| key | meaning |
|---|---|
| `language` | `en` or `ru` (also in the tray menu) |
| `scale` | window scale, 0.6–4.0 (default 1.35; also "Larger" / "Smaller" in the tray menu) |
| `opacity` | window opacity, 0–1 |
| `topmost` | keep the window above all others |
| `warnPercent` / `critPercent` | yellow and red thresholds |
| `expanded` | details expanded |
| `showStats` / `showStatus` / `showSessions` / `showAccount` | show the corresponding block |
| `showMascot` / `showSky` | Clawd and the sky behind him |
| `weatherLat` / `weatherLon` | coordinates for weather; empty — by IP |
| `refreshSeconds`, `usageIntervalSeconds`, `versionIntervalSeconds`, `statusIntervalSeconds`, `accountIntervalSeconds`, `weatherIntervalSeconds` | polling periods, seconds |
| `left` / `top` | window position, written when you drag it |

## Troubleshooting

Errors in the update loop never crash the widget: the bottom-right corner shows
"error" and details go to `widget-error.log` next to the script.

If you edit the scripts: `.ps1` files must stay **UTF-8 with BOM** — without it
Windows PowerShell 5.1 reads them as ANSI and breaks on non-ASCII text. Syntax
check:

```powershell
foreach ($f in @('.\widget.ps1') + (Get-ChildItem .\lib\*.ps1).FullName) {
    $err = $null
    [void][System.Management.Automation.Language.Parser]::ParseFile((Resolve-Path $f), [ref]$null, [ref]$err)
    if ($err) { $f; $err }
}
```

## How it's built

`widget.ps1` is the entry point: single instance, loads the modules from `lib\`
and runs the WPF loop. The window layout is in `widget.xaml`. Modules are
dot-sourced into one shared script scope in a fixed order; each may rely on the
ones loaded before it. All UI text lives in `lib\i18n.ps1` — adding a language
is one more table there.

`tools/` holds the recorder that made the GIFs in this README: it boots the
widget with scripted fake data and renders frames straight from WPF. It needs
ffmpeg and Pillow; the widget itself doesn't.

## License

[MIT](LICENSE)

---

Not affiliated with Anthropic. Clawd and Claude are Anthropic's.
