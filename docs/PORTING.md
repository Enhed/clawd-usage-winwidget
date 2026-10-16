# Porting Clawd Usage

The widget is Windows-only (PowerShell 5.1 + WPF), but the useful part is small
and platform-neutral: two data sources and a handful of rules. This page is
everything you need to build the same thing for macOS, Linux, a phone, a status
bar or anything else. Point Claude at it and the repo, and you're most of the
way there.

If you make a port, open an issue or PR with a link and it'll go into the
README.

## 1. Limits: `claude -p /usage`

```
claude -p /usage --output-format text
```

Prints the same numbers as `/usage` inside Claude Code. **No model call, no
tokens spent.** Takes about two seconds, so run it asynchronously; the widget
polls every 60 s.

> Don't run it from Git Bash / MSYS: it rewrites `/usage` into a path and the
> prompt goes to the model, spending tokens. Any normal shell, or spawning the
> process directly with an argument array, is fine.

Sample output:

```
You are currently using your subscription to power your Claude Code usage

Current session: 10% used · resets Oct 17, 5:19am (Europe/Moscow)
Current week (all models): 26% used · resets Oct 19, 5:59am (Europe/Moscow)
Current week (Fable): 19% used · resets Oct 19, 5:59am (Europe/Moscow)

What's contributing to your limits usage?
Approximate, based on local sessions on this machine — does not include other devices or claude.ai. Behaviors are independent characteristics, not a breakdown.

Last 24h · 1043 requests · 28 sessions
  73% of your usage was at >150k context
  21% of your usage went to always-on context over 40k tokens
  13% of your usage came from subagent-heavy sessions
  Top skills: /dataviz 2%, /chrome-browser 1%
  Top subagents: general-purpose 1%
  Top MCP servers: claude-in-chrome 1%

Last 7d · 4558 requests · 83 sessions
  78% of your usage was at >150k context
  ...
```

Parsing (regexes as used in [`lib/usage.ps1`](../lib/usage.ps1)):

| value | regex |
|---|---|
| session % and reset | `Current session:\s*(\d+)%(?:[^\r\n]*?resets\s*([^\r\n]+))?` |
| week % and reset | `Current week \(all models\):\s*(\d+)%(?:[^\r\n]*?resets\s*([^\r\n]+))?` |
| Fable week % and reset | `Current week \(Fable\):\s*(\d+)%(?:[^\r\n]*?resets\s*([^\r\n]+))?` |
| reset stamp | `([A-Za-z]{3})\s+(\d{1,2}),\s*(\d{1,2})(?::(\d{2}))?\s*([ap]m)` |
| 24h / 7d block | `^Last 24h[^\n]*?(\d+)\s+requests[^\n]*?(\d+)\s+sessions` + the indented lines below |

Things that bite:

- **No "resets" means 0%, not "no data".** With no usage the window hasn't
  started, so the line has a percent but no reset time.
- **The reset stamp has no year.** Assume the current one; if the result is more
  than a month in the past, it's next year (New Year's Eve).
- Minutes are optional: `6am` as well as `5:19am`. The time zone in brackets is
  your local one, so the widget ignores it.
- The Fable line can be missing. Hide that row instead of showing 0.
- Keep unknown lines from the 24h/7d blocks as is: new metrics show up there
  from time to time.
- If the call fails or times out, keep the last numbers and mark them stale.
- The output is English regardless of the system locale; parse dates with an
  invariant/English culture.

## 2. Live sessions: `~/.claude/sessions/*.json`

Claude Code keeps a registry of running sessions itself, one file per process
(`<pid>.json`). Sample:

```json
{
  "pid": 19620,
  "sessionId": "03b99a3b-...",
  "cwd": "C:\\Users\\me\\Projects\\ccusage-widget",
  "startedAt": 1792192091644,
  "procStart": "134366656907618771",
  "kind": "interactive",
  "name": "ccusage-widget-15",
  "status": "busy",
  "updatedAt": 1792192383327
}
```

| field | meaning |
|---|---|
| `status` | `busy` (working), `waiting` (needs you: permission, question, dialog), anything else is idle |
| `waitingFor` | what it waits for, when `status` is `waiting` |
| `name` | session name; fall back to the last folder of `cwd` |
| `pid` | the Claude Code process |
| `procStart` | process start time, to tell a reused PID from the real one |

**Files outlive their processes.** Only count a file if a process with that
`pid` is alive. On Windows `procStart` is the process start time as a FILETIME
(100 ns ticks since 1601, UTC), and the widget allows 5 s of drift. On other
systems the format may differ; checking that the PID is alive (and, ideally,
is a `claude`/`node` process) is a good start.

Also skip the processes you spawned yourself (your own `claude -p /usage`
probe), or the widget will count itself as a running session.

From this list you get "24 running · 1 working · 2 waiting" and the hover list
(`▶` working, `?` waiting, `○` idle).

## 3. Clawd

Clawd is the crab from the Claude Code welcome screen, drawn from the same
block glyphs: 9 cells by 3 rows, each cell split into 2×4 pixels so the
quadrant glyphs map losslessly. Colour `#D77757`. The glyphs, eye shapes and
every animation sequence (frames are 60 ms) are in
[`lib/mascot.ps1`](../lib/mascot.ps1).

Mood, checked top to bottom:

| condition | mood |
|---|---|
| session ≥ 100% | `dead`: belly-up, X eyes |
| any session `waiting` | `wait`: wide eyes, hops, yellow `?` |
| any session `busy` | `work`: runs edge to edge, focused squint |
| some sessions, all idle | `idle`: wanders, looks around; dozes after 10 min without the cursor |
| no sessions | `sleep`: burrowed in the sand, only eyes out, "z"s |

One-shot events on top:

- **A session finished**: the busy count dropped while the waiting count did
  not grow → crouch and jump with arms up.
- **The 5-hour window reset**: the session reset time moved forward *and* the
  percent dropped → celebrate with confetti.
- **Click**: a random Claude Code animation (jump, spin, peekaboo, wink,
  boop…) plus a heart.

## 4. Hearts and colours

Three hearts with halves are the session limit left:

```
halves = ceil(max(0, 100 - session%) * 6 / 100)    # 0..6
```

So each half is about 16.7%, and zero hearts happen only at 100%, exactly when
Clawd lies down. Fewer hearts make him slower and sleepier: yawns at 4 halves,
sweat at 2, staggering and tripping at 1.

Bar colours: green below 60%, yellow from 60%, red from 85% (red also makes
Clawd sweat).

## 5. Optional extras

All of these are plain HTTP, no keys:

| what | source |
|---|---|
| service status | `https://status.claude.com/api/v2/summary.json` |
| latest Claude Code version | `https://downloads.claude.ai/claude-code-releases/latest` |
| account and plan | `claude auth status` |
| weather for the sky | [Open-Meteo](https://open-meteo.com), location by IP via [ipwho.is](https://ipwho.is) |

The sky palette and sprites are in [`lib/sky.ps1`](../lib/sky.ps1), the
weather codes in [`lib/weather.ps1`](../lib/weather.ps1).
