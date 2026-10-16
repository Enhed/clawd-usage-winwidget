# Changelog

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
