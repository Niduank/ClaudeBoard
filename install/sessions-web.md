---
name: sessions-web
description: Open the live web dashboard of every Claude Code session on this machine and its subagents
allowed-tools: Bash(python3 __REPO__/server.py --open)
---

!`python3 __REPO__/server.py --open`

Reply with one short line, in the language the user writes in, saying the dashboard is open at the URL above (or the error above if it failed). Do nothing else.
