# Changelog

## 1.4.0

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
