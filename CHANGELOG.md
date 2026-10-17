# Changelog

## 1.9.0

- **Themes:** Halloween, Classic, Midnight, Mocha, OLED black and Forest, in the
  tray menu or `"theme"` in `config.json`; they switch at once. Halloween comes
  with a wallpaper of tiny pumpkins, bats and ghosts, and is the default this
  autumn: the default theme follows the season (Halloween in September-November,
  Classic otherwise). `"accent": "#F472B6"` puts your own colour on links and
  the weekly bar.
- **Clawd's skins:** Witch hat, Crown, Top hat, Party, Shades, Frost and Tired
  (paler, with dark circles under the eyes) - his colours plus
  pixel accessories that move with him (a hat stays on while he runs and hops,
  and falls off when he lies on his back). Make your own: a small text file with
  the colours and the pixel art in `<clawdHome>\skins`, picked from the tray
  menu; the format and Clawd's pixel map are in the README.
- **No update loop (#6):** when the update could not put its files in place (a
  folder the widget may not write to - Program Files, Windows' controlled
  folder access), the old version came back without a word and offered the
  same update again and again. Now it says so once, and a click on the
  version opens the release page to update by hand.

## 1.8.3

- **Tasks at set times:** `at: 09:00, 18:00` in a task file instead of
  `every` runs it at these times of day - once each, and once when the PC is
  on again if it was off then. A morning summary is one run a day instead of
  one every ten minutes.
- **Moon phase in the sky's tooltip:** "first quarter, 42% lit". The phase is
  now worked out from where the Sun and the Moon are, not from the average
  lunar month - good to a few hours instead of up to a day, so the moon drawn
  at night is more exact too.

## 1.8.2

- **Recurring tasks answer in fields:** whether to tell you, the message, and a
  one-line summary of the run. Staying quiet is now a flag, not a word the
  model had to remember, so "nothing new" no longer reaches the chat.
- **A task's history is short:** a click on a task shows one line per run
  (brighter - what you were told), scrolled instead of stretching the panel
  off the screen. The next run gets those lines instead of the whole last
  report.

## 1.8.1

- **Quieter recurring tasks:** a run with nothing to tell sometimes said so in
  a sentence ("nothing new since the last run") instead of staying silent, and
  that landed in the chat every ten minutes. The rule is now repeated right
  after the task's text, and a reply ending in NOTHING counts as silence.

## 1.8.0

- **Repeating reminders:** a `repeat:` line in a reminder file - `daily`,
  `weekly`, `monthly` or `yearly` - and when it goes off the widget writes the
  file for the next time (catching up if it was off). "Remind me every 17th" is
  now one reminder, marked ↻ in the Reminders tab, instead of a file per date.
  The chat and Clawd's session on the phone know how to make them; a plain
  repeating reminder no longer turns into a recurring task that spends limits.

## 1.7.1

- **Details on a quiet day:** "Last 24h" and "Last 7 days" stayed empty when
  `/usage` said "1 session" or "1 request" - only the plural was recognised.
  The counts are now worded properly too: "1 request · 1 session".

## 1.7.0

- **Sessions from other machines:** `"remoteSessions"` in `config.json` takes
  a list of URLs or file paths, each serving another machine's live sessions in
  the `~/.claude/sessions` shape (with `host` and `generatedAt`). They count in
  SESSIONS and for Clawd's moods, and the hover list shows the host. A source
  that fails, hangs or goes stale is ignored. Suggested by @Drawmonster (#3).

## 1.6.0

- **No more transcripts from the `/usage` check:** it used to leave a session
  file in `~/.claude/projects` every minute - thousands of them, all showing up
  in `claude --resume` for the widget's folder. Now it runs with
  `--no-session-persistence`. The old files are not removed.
- **The last 7 days in details** (off by default, `"showHistory": true` in
  `config.json`): a chart of the 5-hour and weekly percentages - hover for the
  time, both values and the project busiest in that hour; the first run fills it
  from what earlier `/usage` checks left behind, so it is not empty for a week.
  Below it, the week's top projects: which folders spent the most, estimated
  from Claude Code's transcripts by tokens and model prices.

## 1.5.4

- **Français:** a French UI, in the tray menu under Language or with
  `"language": "fr"`. Reminder times can be typed in French too: `demain 10h`,
  `lun 10:00`, `dans une semaine`, `le ven 18h30`.

## 1.5.3

- **Tray tooltip with reset times:** `"trayResetClock": true` shows each limit
  with its reset as a clock time - `5h: 36% (resets 03:20)`, `7d: 81% (resets
  tmrw 01:00)`, the weekday further off; Fable on a third line when it fits.
  Off by default. Suggested by @g3ocycle (#2).
- `docs/PORTING.md`: what a port to macOS, Linux or a phone needs - the
  `/usage` and session formats, parsing gotchas, Clawd's moods and the hearts.

## 1.5.2

- Fixed: looking a task up by name found every task - removing one from the chat
  (`task-remove`) would have removed them all, Allow could write to the wrong
  task, and a queued run could start the wrong one.
- "Run now" while another task runs queues it ("queued") instead of hiding the
  button on every task.
- An empty answer is retried once on the chat model before it counts as a failure.
- Each task is a card of its own, with its links right under the name and the
  reports below them.
- `tools\tasks-test.ps1`, run by `smoke.ps1`: the task queue, the retry and
  removing one task, without calling Claude.

## 1.5.1

- **A task refused a permission says so:** the chat shows a card with the missing
  rules (`PowerShell(gh issue list:*)`, `WebFetch(domain:...)`, an MCP tool) and
  **Allow** adds them to the task's `tools` and runs it again. `tools` takes such
  rules now, not only MCP servers.
- A run that ends without any answer is a failure shown on the task, not taken
  for "nothing new".
- The task gets its last run time with the time zone and in UTC, so it compares
  correctly with GitHub's or mail's UTC times.

## 1.5.0

- **Mail actions need a click** unless AUTO is on: the chat reads with your
  tasks' tools at once, but moving, marking or sending shows up as a card with the
  exact call and Run / Not now.
- **Tasks wait while usage is high:** at `tasksMaxPercent` (80%) of the session or
  the week, or a task's own `limit`. The Reminders tab says when a task waits.
- **Task history:** a click on a task shows its latest reports and the last error.
- **Self-update rolls back:** if the new version does not come up in five
  minutes, the old files come back, the old version starts and says so; that
  version is not offered again.
- **No more silent hangs:** the widget runs with `-NonInteractive` and never asks
  PowerShell questions; an error while starting goes to `widget-error.log`.
- `tools\smoke.ps1` - the pre-release check: start with junk in TEMP, update and
  rollback, each in a sandbox next to the running widget.

## 1.4.1

- Fixed: the widget could hang at start, without a window, when a folder was
  left among its temp files (an unpacked update) - deleting it asked a
  question nobody could see. The update now also cleans up after itself.

## 1.4.0 (withdrawn - could hang at start; use 1.4.1)

- **The widget tells about its own updates:** once an hour it asks GitHub for the
  latest release. A new one turns the version in the corner into a yellow
  "Clawd X is out" with what's new on hover, and a Windows notification comes
  once per version. A click downloads the release, replaces the files and
  restarts the widget; `config.json` and the other local files stay. In a git
  clone the click opens the release page instead.

## 1.3.0

- **Recurring tasks:** files `tasks\<name>.md` in Clawd's home with `every`,
  `tools` (an MCP server as `mcp__<server>`), optional `hours`, `model`, `paused`.
  The widget runs a due one as a background `claude -p` with the context and the
  last report; only replies worth telling reach the chat, with a notification.
  Made from the chat (`task` / `task-remove` blocks), the phone or by hand; listed
  on the Reminders tab with Run now, Pause, Open, Delete. The chat sees the recent
  reports and may use the tasks' tools, so "move it to the trash" after a mail
  report works; mail goes out only after a shown draft and a yes. "Every 30
  minutes" in the reminder form hands the request to the chat.
- **AUTO in the chat** (`chatAutoRun`): Clawd's scripts run without the Run click,
  up to three in a row.
- **"When" in reminders** understands `in a week`, `через месяц`, `через полчаса`,
  `через неделю 15:00`; anything else is not red any more - on saving it goes to a
  small model (`quickModel`), and only what it can't place is an error.
- Usage at 0% with no five-hour window started shows `0`, not `--`.

## 1.2.0

- **Tabs in Clawd's panel:** Chat, Reminders, Lists.
- **A reminder that goes off is a card** in the bottom-right corner, like a phone
  notification: put it off (+15m, +1h, +3h, tomorrow 9:00, or any time) or mark
  it done. It stays until answered; several stack up.
- **Reminders tab:** what's coming with Change, +1 hour and Delete; a form to add
  one with a "when" field that understands 18:30, tomorrow 10, +20m, mon 9:00,
  19.10 14:00 and shows what it made of it, plus quick picks; recently fired ones
  with "again".
- **Lists tab:** shopping and any other lists - markdown files with checkboxes in
  Clawd's home (`lists\<name>.md`). Add several items at once with commas, tick
  them off, remove ticked ones; new lists with "+". The chat changes them through
  `list-*` blocks, Clawd's own session edits the files - "add milk to shopping"
  works from the phone too.
- The panel no longer stays on top of other windows unless the widget does
  (`topmost`).
- Tips get **Do it** (Clawd answers with a script to approve) and **Refine**.
- An error in a click handler is logged to `widget-error.log` instead of closing
  the widget.

## 1.1.0

- **Clawd's panel.** An icon in the header opens a panel beside the widget with
  tips and a chat. The icon shows what is waiting: a bell for a reminder, a blue
  chat for a new reply, a lamp with a number for tips.
- **Tips.** Every half hour a background look over the computer: low disk space and
  what takes it (temp folders, Downloads, Recycle Bin, package caches), new
  autostart entries, apps not started for a long time, a pending restart, memory
  and CPU hogs. Read-only, local, no tokens.
- **Chat with Clawd.** Ask about the computer, answer a tip ("clean it all up"),
  set reminders. Clawd can look around but not change anything: changes come as
  a script with "Run", "Refine" and "Not now". Reminders fire with a Windows
  notification. Uses `claude -p` and your plan's limits (`chatModel`, Sonnet by
  default).
- **Clawd's home and his own session.** The chat works in Clawd's home folder
  (`clawdHome`); reminders are files there (`reminders\YYYY-MM\...md`) that the
  chat, Clawd's session or you can make; the tips are written to `tips.md`. With
  `clawdSession` the widget keeps Clawd's own Claude Code session running there
  with Remote Control, to talk to him from the phone; it comes back to its own
  conversation and is restarted if it's gone. The panel shows the phone
  conversation in its feed and the two know about each other (`chat-log.md`);
  `/clear` on the phone starts a new conversation in the same entry.
- **Run as administrator** (`runAsAdmin`): the widget restarts itself elevated
  through UAC; tips then also read Prefetch and system folders.
- The widget's own version: in the tray menu, the panel and next to Claude Code's
  version. Clicking Claude Code's version opens its changelog (or updates, when
  an update is out), clicking the widget's — this file on GitHub.

## 1.0.0

- First release: plan limits from `claude -p /usage`, Clawd, the sky, sessions,
  service status, account and version, tray icon, English and Russian.
