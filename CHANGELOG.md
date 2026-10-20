# Changelog

## 1.18.0

- **Cyberpunk theme**, animated: a night in a neon megacity. Scanlines, neon
  rain and the city's glow behind the widget, a glitch tearing across in red and
  cyan now and then, searchlights sweeping the sky; in the sky row a skyline with
  flickering windows, a tall tower with a blinking beacon, neon signs that stutter
  ("2077" on a roof) and flying cars crossing between the towers. Two skins
  go with it: Rockerboy (slicked-back hair, gold aviators, a goatee and a chrome
  arm) and Netrunner (a dark visor with glowing cyan slits and a neural rig).

## 1.17.1

- Text in chat messages can be selected and copied in part (Ctrl+C or right-click);
  the icon that copies the whole message moved to its bottom corner, where it is
  at hand at the end of a long reply. ([ce83282](https://github.com/Enhed/clawd-usage-winwidget/commit/ce83282ac3f12979a05b3f8ffc524cad48c0968a))

## 1.17.0

- **Commands and tasks without admin rights.** With the widget running as
  administrator, everything it started was elevated too. Now action commands
  and recurring tasks run with your usual rights; the chat and Clawd's actions
  stay elevated. Turned off in Settings → Window (`jobsNoAdmin`) - for commands
  that need admin rights. ([14fbd6f](https://github.com/Enhed/clawd-usage-winwidget/commit/14fbd6f0464c39cef99a7ad9bd99a0ae2e15d0d0))
- Clawd knows what runs with which rights: elevated, he is told his commands
  and scripts run as administrator with no UAC to stop a mistake; not elevated -
  that system folders and services are out of reach, and where to turn it on. ([0be2e35](https://github.com/Enhed/clawd-usage-winwidget/commit/0be2e35a5ebf3d47f23a75f9907c0ed5fd64319f))
- The Tasks form understands "how often" in your own words, as reminders do:
  what it doesn't know ("twice an hour in the daytime", "every morning at eight")
  goes to the small model on saving and comes back as a schedule. Days of the
  week still can't be set. ([375d6af](https://github.com/Enhed/clawd-usage-winwidget/commit/375d6afb42671180ef619e0c88efb7fb146908a1))

## 1.16.0

- **Tasks get a tab of their own.** Recurring tasks moved out of Reminders to a
  new Tasks tab, with a form to make one by hand: a name, what to do and how
  often (`10m`, `2h`, `1d`, `09:00, 18:00`, hours at the end: `10m 8-23`).
  An existing task can be changed there too; its permissions, model and history
  stay.
- **Actions**: a new tab for things you run with a click - a command or a
  mini-skill for Clawd. A command is run by the widget itself, no Claude and no
  tokens: a program, file or link is opened, anything else runs as PowerShell,
  and its exit code and output are kept; a running one can be stopped. "Clawd
  does it" sends the words to the chat. Save one under a name to keep it as a
  card, or run it just once without a name.
- Task and action cards are compact: the name with icons on the right (run,
  change, pause, delete); a click on the card opens what is inside.
- Every panel tab shows how much it holds, Lists - the items still to tick off.
- **The panel's tabs can be turned off** in Settings → Clawd: Reminders, Tasks,
  Actions, Lists. One turned off is gone from the panel and does nothing in the
  background, and Clawd is told so.

## 1.15.1

- Fixed: after switching from the Halloween theme to another one the sky row
  vanished, taking the animated themes' sky layer (planets, moon, jellyfish)
  with it until restart.

## 1.15.0

👻 **Halloween update**: the Halloween theme is animated now, and Clawd has
four spooky skins to dress up in.

- **Halloween theme comes alive**: fog creeping along the bottom of the widget,
  green will-o'-the-wisps, bats flapping across, a ghost floating by now and
  then and a spider letting itself down from its web in the corner; in the sky
  row a big moon over a graveyard - tombstones, a cross, a dead tree and
  jack-o'-lanterns with a flickering candle inside.
- **Four Halloween skins** for Clawd: Zombie crab (rotting green, a wound and
  torn rags), Skeleton crab (a skull and ribs), Frankenstein crab (a flat
  top, a scar, neck bolts and a dark jacket) and Dracula crab (red eyes, fangs,
  a widow's peak and a cape with a high collar).

## 1.14.0

- **Nine new skins** for Clawd: Head tie (a striped tie knotted on top of his
  head), Orange parka, Green ushanka, Pompom beanie, Cyan beanie, Square pants,
  Flower shorts, Red crab and Fry cook hat.

## 1.13.0

- **Space theme** (Settings → Look), after the one in
  [clawd-usage-mac](https://github.com/fl03er/clawd-usage-mac) by @fl03er: a
  twinkling starfield with drifting nebulae and a shooting star now and then
  behind the whole widget; in the sky row two slowly turning pixel planets, one
  of them ringed, and a little ship crossing take the weather's place.
- **Underwater theme**: a cartoon sea - sunbeams swaying down and bubbles rising
  behind the widget; in the sky row pastel flowers drifting like clouds, kelp
  swaying on the sand by a starfish, fish swimming across and a jellyfish.
- **Astronaut skin** for Clawd: a glass helmet with a glint and a suit collar.

## 1.12.4

- **Reset time:** also read when `/usage` prints it as `Oct 17 at 2:29pm`,
  without the comma, as some Claude Code versions do.

## 1.12.3

- **Remote Control of Clawd's session:** when a resumed session could not
  reconnect to Remote Control, it kept running unreachable from the phone. Now
  the widget notices it and restarts the session as a fork of the same
  conversation (a new Remote Control session), and if that fails too - as a
  fresh conversation.

## 1.12.2

- **Links in the chat:** an http(s) address or a markdown `[text](url)` in a
  message is a link - a click opens it in the browser.

## 1.12.1

- **Pasting into the chat:** a multi-line text is pasted whole - before, only
  its first line got into the field.

## 1.12.0

- **Copy from the chat:** an icon in a message's corner on hover (a tick once
  copied), or right-click for Copy; for a script it copies the text together
  with the code.
- **Full access for the chat** (Settings → Clawd, `chatBypass`, off by
  default): the chat runs in Claude Code's `bypassPermissions` mode, so Clawd
  reads files anywhere on the computer, not only in his folder, and no call is
  refused. Changes still come as `run` scripts.
- **Clawd as a full agent** (Settings → Clawd, "Short replies and quick
  checks", `chatCompact`, on by default): turned off, the chat's prompt drops
  the tiny-chat rules - no short replies, no quick-check limits, no
  `chatTimeoutSeconds`; Clawd helps with anything, as fully as needed.
- **Stop a reply:** while Clawd answers, the Send button turns into Stop.
- **What Clawd is doing:** instead of "Clawd is thinking..." the line under the
  conversation shows the current step - "Reading win.ini", "Running:
  Get-ChildItem...", "Searching the web: ...", "Writing the reply" (the chat
  reads Claude Code's `stream-json` output as it comes).

## 1.11.0

- **Claude Code tab in Settings:** Claude Code's own `~/.claude/settings.json`,
  a picked set of keys with a hint for each: the model of new sessions, fast
  mode, language of answers, the permission mode at start, auto-compact, auto
  memory, checkpoints for `/rewind`, the byline in commits and PRs, how long
  sessions are kept, the update channel, the terminal theme, renderer, answer
  style and transcript view, tips, turn duration, thinking summaries, Remote
  Control in every session and pushes to the phone. Only the changed key is
  rewritten, in Claude Code's own format; the file as it was before the first
  change is kept as `settings.json.clawd-bak`. `CLAUDE_CONFIG_DIR` is honoured.

## 1.10.1

- Clawd no longer trudges into the wall once a session finishes: the edge he
  was running to while Claude worked is forgotten when the work is over.

## 1.10.0

- **Settings window:** the gear in the window's header (or Settings in the tray
  menu) opens Clawd-styled settings with three tabs. Look: language, theme
  chips with a swatch of each, and Clawd's skins as cards with a live preview -
  he raises his arms under the mouse, a click puts the skin on. Window: size,
  opacity, always on top, which blocks the window shows, the tray tooltip's
  clock, run as administrator. Clawd: tips, chat and its auto-run, recurring
  tasks, his Remote Control session. Everything applies at once; the rest of
  `config.json` is one link away at the bottom.
- The tray menu is down to show/hide, refresh, settings and exit.
- In a git clone, a click on "Clawd X is out" opens the changelog instead of
  the release page.

## 1.9.3

- **`CLAUDE_CONFIG_DIR` is respected:** with Claude Code's folder moved away
  from `~/.claude`, the widget kept reading the old one - sessions, the 7-day
  projects, the phone conversation, the update channel and the trusted-folder
  check went stale. Every path into that folder now goes through one helper
  (`Get-ClaudeConfigDir` in `lib/config.ps1`). By @g3ocycle (#7).

## 1.9.2

- **New skin:** Nerd - square glasses with tape on the bridge.

## 1.9.1

- **New skins:** Santa hat, Cat ears and Bow.
- The "Clawd X is out" tooltip leaves out the pictures of a release's notes
  instead of showing their links.

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
