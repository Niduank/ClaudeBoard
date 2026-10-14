<!--
  README.md
  ClaudeDashboard

  Created by Kévin Naudin on 11/10/2026.
-->

<p align="center"><img src="assets/logo.svg" width="96" alt="Claude Dashboard logo"></p>

# Claude Dashboard

A live recap page of every Claude Code session running on this Mac, served on `http://localhost:7788`.

Built for someone running many sessions across projects at once: it shows at a glance which sessions are
working, which ones wait for you (and why), and lets you jump to or answer a session without hunting for its terminal.

- Sessions grouped by state: running, waiting for you, inactive or frozen; the latest answer first
- Per session: current tool, last prompt and answer, one-line Haiku summary, git state of the folder,
  context fill, subagents, messages exchanged with other sessions
- Badges: Question, To test, unread answers since your last visit
- Detail drawer with the recent conversation; reply from the page (typed into the session's terminal)
- Open a session's terminal (Ghostty or iTerm2), start a new session (same folder, or any folder under a root), close a session
- Desktop notifications when a session starts waiting for you
- Optional access from other devices through Tailscale (`tailscale serve`, tailnet only)

The page is in English or French: `install.sh` sets the default, and the EN / FR switch at the top right of the page
switches this browser. Code and docs are in English.

## Requirements

`install.sh` checks these and offers to install what is missing (Homebrew casks for the apps).

| Dependency | Needed for | Required |
| --- | --- | --- |
| macOS | `ps`, `osascript`, LaunchAgent | yes |
| Python 3.9+ (stdlib only, no `pip install`) | the server | yes |
| Claude Code, logged in | reading sessions; Haiku summaries | yes |
| [Ghostty](https://ghostty.org) 1.3+ (AppleScript support) or [iTerm2](https://iterm2.com) | open / reply / new session / close buttons | no, the page is read-only without one |
| Google Chrome | `--open` shows the page as an app window | no, falls back to the default browser |
| Tailscale | access from the iPhone | no |

## Install

```sh
git clone https://github.com/Niduank/ClaudeDashboard.git
cd ClaudeDashboard
./install.sh
```

Then open http://localhost:7788. The repo can live anywhere, in a path without spaces. The script, safe to run again:

1. Checks the dependencies above and offers to install the missing ones.
2. Asks for the project roots: "New session…" offers every subfolder of them. It suggests the folders that hold
   the most projects Claude Code has opened (from `~/.claude.json`); answer with numbers and/or paths.
   On a reinstall, Enter keeps the current roots.
3. Asks for the board language (English or French, the macOS language by default), then, with both Ghostty and
   iTerm2 installed, which one *New session* opens in.
4. Writes the LaunchAgent `~/Library/LaunchAgents/io.github.niduank.claude-dashboard.plist` (your `PATH`, the roots, the language, the terminal),
   restarts the server and waits until it answers.
5. Writes the `/sessions-web` command to `~/.claude/commands/`, and adds a `PermissionRequest` hook to
   `~/.claude/settings.json` (`board_dialog_hook.py`) so the page can show what an open dialog asks.
   Only that entry is added (the other settings are kept; the file is rewritten with a 2-space indent).
   Open sessions pick it up at once.
6. Offers a `Claude Dashboard` app on the Desktop that opens the page, like `/sessions-web`; a reinstall refreshes it.
7. Optionally serves the page on your tailnet (see [Access from the iPhone](#access-from-the-iphone-tailscale)).

- launchd keeps the server alive (`KeepAlive`, restarted at most every 10 s); errors go to `server.log`.
- `/sessions-web` in any Claude Code session opens the page (it starts the server first if needed).
- The first click that drives a terminal triggers a macOS automation prompt for `python3`: allow it (once per terminal app).
  To change it later: System Settings > Privacy & Security > Automation.

If you move the repo, change Python, or want other roots, run `./install.sh` again.
To try it without installing: `python3 server.py` (foreground, Ctrl-C to stop).

### Update

```sh
git pull
launchctl kickstart -k gui/$(id -u)/io.github.niduank.claude-dashboard   # only needed when server.py changed
```

After a pull that changes `install.sh`, or from an install made before it existed, run `./install.sh` again instead
(Enter keeps the current roots): an older LaunchAgent has no project roots, so "New session…" lists only live sessions' folders.

`page.html` is read on every request: reloading the page is enough after a change to it.
An open page notices a server restart (new token) and reloads itself.

### Uninstall

```sh
./install.sh --uninstall
```

It stops the server and removes the LaunchAgent, `/sessions-web`, the dialog hook and the Desktop app. A tailnet serve stays:
`/Applications/Tailscale.app/Contents/MacOS/Tailscale serve --https=443 off` removes it.

## Using the page

The page refreshes every 3 seconds; it holds off only while you are typing a reply (up to 15 s after the last key).
When `page.html` changes, an open page reloads itself, unless a reply is being written or sent.

**States**

| Label | Meaning |
| --- | --- |
| Running (En cours) | The session is working (Claude Code marks it busy, or a shell command runs) |
| Your turn (À toi) | The turn ended: the session waits for you |
| Question | Waiting, and the last answer ends on a question or offers numbered options |
| To test (À tester) | Waiting, and the last answer asks you to test something on a device |
| Frozen (Figée) | Marked busy, but no message for 1 hour and no subagent at work |
| Inactive (Inactives) | Frozen sessions and sessions with nothing new; hidden unless the "Inactive" chip is on |

A dot on a card marks an answer you have not opened yet; the "Waiting for you" header counts them
(read state is kept in this browser's `localStorage`).

**Card**: name, folder, branch, model, context fill, uncommitted files and unpushed commits, the tool being run,
the summary, the last prompt and answer, active subagents, the last message to or from another session.

**Detail drawer** (click a card or press Enter): the last 60 exchanges, tool calls folded into one line,
peer messages, and a reply field. Past 3 subagents, their list folds into one line (tap to unfold).
The browser's back button or gesture closes the drawer and returns to the list.

**Toolbar**: search (name, project, branch, answer text), "By project" groups cards by folder,
"Inactive" shows idle sessions, "New session…" starts a session in a subfolder of a project root,
"Enable alerts" asks for notification permission.
The EN / FR switch at the top right sets the page language (kept in this browser).

**Keyboard**

| Key | Action |
| --- | --- |
| `j` / `k` (or arrows) | Move between sessions |
| `Enter` | Open the detail drawer |
| `o` | Focus the session's terminal |
| `r` | Reply to the session |
| `⌘ Enter` / `Ctrl Enter` | Send the reply (`Enter` adds a new line) |
| `/` | Search |
| `Esc` | Cancel a reply being sent, clear the search, leave the reply field, close the drawer |

**Actions that drive the terminal**

The page drives Ghostty and iTerm2. Each session's terminal is read from its process tree
(claude < shell < login < Ghostty, or < iTermServer for iTerm2) and named on its buttons.

- *Open*: in iTerm2, focuses the session whose tty is the one `claude` runs on (an exact match). In Ghostty, which
  exposes no tty, focuses the terminal whose title is the session name, or the only terminal in the session's folder.
- *Reply*: after a 2 second delay (an "Undo" button in the toast, or `Esc`, cancels it and puts the text back), types the
  text (Enter adds a new line; the "Send" button or ⌘+Enter / Ctrl+Enter sends; 2000 characters max) into that terminal as a paste (so a new line never submits early) and presses Enter. It works while
  Claude is working too: Claude Code queues the message for the running turn. The card shows it at once as
  "You · sent" until the transcript has it (a queued message is written only when the running turn takes it).
- *New session*: opens a tab in the folder and runs `claude --dangerously-skip-permissions`, from the drawer
  (the session's folder) or the toolbar (any subfolder of a project root). In a folder Claude Code does not trust yet,
  its trust dialog shows first: the session appears on the page once it is answered in the terminal. The tab opens in
  Ghostty, or in iTerm2 when `BOARD_TERMINAL=iterm` is set (see Configuration).
- *Close the session* (drawer, then confirm): hangs up the shell that runs `claude`, which ends the session
  and closes its tab; a background session is stopped with `claude stop`. The conversation stays resumable.
  The shell is found from the process tree, never from a title: two sessions can share a name.
  A session outside a Ghostty or iTerm2 tab is not closed from the page.
- *Answer* a dialog the hook saw, from the dialog box: the page replays the keystrokes in the terminal, after the same
  2 second delay and with the same "Undo". A question's options are buttons: with one single-choice question a click
  answers; otherwise toggle the options, then *Send choices*. A permission has *Allow once* / *Deny*, a plan
  *Approve (auto mode if available)* / *Deny* (approve sends option 1, "Yes, and use auto mode" when Claude Code offers it).
  Free text and "deny with an instruction" go through the reply field (Escape, then the text). Answers and replies are sent
  one at a time. Keystrokes were measured in Ghostty only; iTerm2's are untested live.
- Ghostty: when several terminals have the session's title, replies and answers are refused unless exactly one is in the
  session's folder (it would type into the wrong tab).
- Background sessions (`claude --bg`) have no terminal: open and reply are disabled for them.
- A reply while a dialog is open in the session (permission, question, plan; `status: "waiting"`) first presses
  Escape, which dismisses the dialog ("no / cancel"), then sends the text: Enter alone would answer the dialog,
  often with "Yes". The card shows what the dialog asks: the question and its choices, the command to allow,
  or the plan to approve (stored by the dialog hook as the dialog opens: Claude Code writes the tool call
  to the transcript only once it is answered). Other dialogs (`waitingFor: "dialog open"`, such as usage
  credits or managed settings) are answered in the terminal: Escape may not close them.

## Access from the iPhone (Tailscale)

1. Install Tailscale on the Mac and the iPhone with the same account; enable MagicDNS and HTTPS certificates
   (Tailscale admin console > DNS).
2. Answer yes to the tailnet question of `./install.sh`. It waits until the Mac is logged in, writes `tailnet.json`
   (the tailnet identity the server accepts; the app's CLI does not answer under launchd), runs
   `tailscale serve --bg http://127.0.0.1:7788` and prints the `https://<mac>.<tailnet>.ts.net` URL.
3. On the iPhone, open that URL; Share > Add to Home Screen gives a full-screen app with the Claude Dashboard icon.

The serve config persists across restarts. The server starts the Tailscale app at login and again within a
minute if it is ever quit (the App Store build does not start at login by default); a manual disconnect is left as is.

## How it works

Everything comes from files Claude Code writes locally; nothing is sent anywhere except the summary prompts.

| Source | Read for |
| --- | --- |
| `~/.claude/sessions/<pid>.json` | the list of sessions: pid, session id, folder, name, `kind` (interactive / bg), `status` (busy / idle / shell / waiting, with `waitingFor`, while a dialog is open) |
| `ps -p <pids>` | drops session files left by crashed processes |
| `~/.claude/projects/<folder with non-alphanumerics as ->/<session id>.jsonl` | title, last prompt and answer, current tool, model, token usage, peer messages |
| `.../<session id>/subagents/*.jsonl` and `*.meta.json` | subagents updated in the last 30 minutes |
| `git -C <folder> status` / `rev-list` | uncommitted files, commits on no remote (cached 30 s per folder) |
| `dialogs/<session id>.json` | what the open dialog asks, written by `board_dialog_hook.py` (a Claude Code `PermissionRequest` hook) as it opens; ignored once older than the session's switch to `waiting` |

These are Claude Code's internal files, not a public API: a Claude Code update can change them and break
part of the page. Transcripts are read incrementally (only the bytes appended since the last poll).

**Summaries**: when a session's turn ends with a new answer, the server runs
`claude -p --model haiku` (one at a time, 90 s timeout) on the last prompt and answer and stores the sentence in
`summaries.json`, in the `BOARD_LANG` language (changing it writes the summaries again).
They use your Claude Code login and count toward its usage (`ANTHROPIC_API_KEY` is removed
from their environment). Runs happen in `summarizer/`, which is filtered out of the page.

### Files

| File | Role |
| --- | --- |
| `server.py` | HTTP server, session scan, summaries, Ghostty and iTerm2 AppleScript, session close, Tailscale keep-alive |
| `page.html` | The single page (vanilla JS, no build step); `__TOKEN__` is replaced on each request |
| `install.sh` | Install, reinstall, `--uninstall`; writes the LaunchAgent and the dialog hook |
| `test_dialogs.py` | Tests of the dialog answers (`python3 test_dialogs.py`, plain asserts) |
| `board_dialog_hook.py` | Claude Code `PermissionRequest` hook: stores what an opening dialog asks in `dialogs/`; never answers it (no output) |
| `install/sessions-web.md` | The `/sessions-web` Claude Code command template (`__REPO__`) |
| `assets/logo.svg` | The logo: favicon (the number of sessions waiting for you is drawn on it), README, home screen |
| `assets/apple-touch-icon.png`, `assets/ClaudeDashboard.icns` | The logo rendered for the iPhone home screen (180 px, full bleed) and the Desktop app |

Runtime files (git-ignored, personal to the Mac): `summaries.json`, `server.log`, `tailnet.json`, `summarizer/`.

### HTTP API

| Method | Path | Body | Returns |
| --- | --- | --- | --- |
| GET | `/` | | the page |
| GET | `/api/sessions` | | `{"sessions": [...], "folders": [...]}` |
| GET | `/api/history?pid=<pid>` | | `{"items": [...]}`, the drawer conversation |
| POST | `/api/focus` | `{"pid": 123}` | `{"message": "..."}` |
| POST | `/api/reply` | `{"pid": 123, "text": "..."}` | `{"message": "..."}` |
| POST | `/api/answer` | `{"pid": 123, "at": 1760000000000, "answer": ...}`, `at` = the dialog's `at`; `answer` = `{"choices": [[0], [1, 2]]}` (0-based, per question) or `{"decision": "allow"\|"deny"}` | `{"message": "..."}` |
| POST | `/api/new` | `{"cwd": "/path"}`, a live session's folder or a subfolder of a project root | `{"message": "..."}` |
| POST | `/api/close` | `{"pid": 123}` | `{"message": "..."}` |

`/api/answer` returns 400 for an invalid answer (also outside Claude Code's 1-4 questions / 2-4 options), 404 for an unknown
session, 409 when the dialog changed, was already answered or closed, or the Ghostty tab is ambiguous, 500 when the terminal refuses.

POSTs need `Content-Type: application/json` and the `X-Board-Token` header embedded in the page.

### Configuration

No config file: the constants at the top of `server.py` (`PORT`, `CHROME`, `TAILSCALE_APP`,
`NEW_SESSION_INPUT`, time windows) and of the `<script>` in `page.html` (`FROZEN_MS`, `CONTEXT_WINDOW`).

Four values come from the environment, which `install.sh` writes under `EnvironmentVariables` in the LaunchAgent:

- `BOARD_PROJECTS_ROOTS`: the project roots, colon-separated (no default: "New session…" then offers only live sessions' folders).
- `BOARD_LANG`: `en` (default) or `fr`, the language of the page by default, of the server's messages (a page asks for
  its own with `X-Board-Lang`) and of the summaries.
- `BOARD_TERMINAL`: the app *New session* opens a tab in, `ghostty` (default) or `iterm`; open, reply and close always
  use the session's own terminal.
- `PATH`: where `claude` is found (`~/.local/bin/claude` if it is not on it).

## Security

- The server listens on `127.0.0.1` only and checks the `Host` header (blocks DNS rebinding).
  The tailnet name is accepted only when Tailscale names the owner's login.
- Every POST needs a per-launch random token embedded in the page; a stale page reloads itself.
- Replies are typed into the terminal as an argv item, never interpolated into a script; each send is logged
  (time, session, terminal, never the text) in `server.log`; so is each answer (`answer pid=… … ok=…`, never option labels).
- An answer must carry the open dialog's `at`: one already answered or replaced is refused, never typed into the next dialog.
- Summaries run `claude -p` with Haiku, no tools, no user settings, hooks, plugins or MCP servers, and no session persistence.
- The page shows prompts and answers of every session: anyone who can open it can read them.
- The dialog hook only writes what a dialog asks to `dialogs/` (in the repo, git-ignored); it prints nothing,
  so it never approves or denies anything.
- The page starts sessions with `--dangerously-skip-permissions` (also from the tailnet) and closes sessions:
  anyone who can open it can run an agent without permission prompts. `/api/new` only accepts a live session's folder
  or a listed subfolder of a project root, never a free path.

## Troubleshooting

| Symptom | Check |
| --- | --- |
| Page does not load | `launchctl print gui/$(id -u)/io.github.niduank.claude-dashboard`, `server.log`, port taken: `lsof -i :7788` |
| Errors not in the log | stop the agent (`launchctl bootout ...`), run `python3 server.py` in a terminal |
| "Ghostty terminal not found" (FR: "Terminal Ghostty introuvable") | the terminal title is not the session name and several terminals share its folder: rename the session (`/rename`) or close the extra terminal |
| "Ghostty refused ...", "iTerm2 refused ..." (FR: "... a refusé ...") | automation permission for `python3` (System Settings > Privacy & Security > Automation) |
| No summaries | `claude -p --model haiku "hi"` must answer; otherwise log in, or run `./install.sh` again if `claude` moved |
| 403 from the tailnet URL | `tailnet.json` missing or stale (renamed Mac, other account): run `./install.sh` again, yes to the tailnet question |
| A session is missing | it runs on another machine, or its `~/.claude/sessions/<pid>.json` is gone |

## Heuristics (`ponytail:` comments)

- A subagent is active if its transcript was written in the last 2 minutes.
- A session is frozen if it is marked busy with no message for 1 hour and no active agent.
- Question / To test badges match keywords at the end of the last answer, French or English phrasing whatever the page language.
- The context window is assumed to be 1M tokens.

## License

[MIT](LICENSE)
