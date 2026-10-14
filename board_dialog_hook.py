#!/usr/bin/env python3
#
#  board_dialog_hook.py
#  ClaudeDashboard
#
#  Created by Kévin Naudin on 14/10/2026.
#
#  Claude Code PermissionRequest hook (installed by install.sh): it runs as a dialog opens (permission, AskUserQuestion,
#  plan approval) and stores what the dialog asks in dialogs/<session id>.json, for the page to show while it waits.
#  Claude Code writes the tool call to the transcript only once the dialog is answered.
#  It never decides anything: no output, always exit 0, so the dialog shows as usual.
#

import glob
import json
import os
import sys
import time

try:
    os.umask(0o077)  # commands and plans: readable by this user only
    event = json.load(sys.stdin)
    args = event.get("tool_input") if isinstance(event.get("tool_input"), dict) else {}
    # only what the page shows, cut: a Write carries the whole file, a MultiEdit nested ones
    kept = {k: v[:6000 if k == "plan" else 300] for k, v in args.items() if isinstance(v, str)}
    if isinstance(args.get("questions"), list):
        kept["questions"] = [{"question": str(q.get("question", ""))[:1000], "multiSelect": q.get("multiSelect") is True,
                              "options": [{"label": str(o.get("label", ""))[:200]} for o in q.get("options") or [] if isinstance(o, dict)][:8]}
                             for q in args["questions"][:4] if isinstance(q, dict)]
    folder = os.path.join(os.path.dirname(os.path.abspath(__file__)), "dialogs")
    os.makedirs(folder, exist_ok=True)
    now = time.time()
    # a file is only read while its session waits: those of ended sessions go after a day
    for old in glob.glob(os.path.join(folder, "*.json")):
        if now - os.path.getmtime(old) > 86400:
            os.remove(old)
    path = os.path.join(folder, os.path.basename(str(event["session_id"])) + ".json")
    # ponytail: one file per session; parallel calls that all need permission show the last one asked,
    # while the terminal may show the first. Each writes its own temp file, so none is torn
    dialog = {"at": now * 1000, "tool": str(event.get("tool_name", "")), "input": kept}
    # another dialog asked under 2 s ago: parallel requests, the page then offers Deny only
    try:
        with open(path) as f:
            last = json.load(f)
        if dialog["at"] - last["at"] < 2000 and (last["tool"], last["input"]) != (dialog["tool"], kept):
            dialog["several"] = True
    except Exception:
        pass
    tmp = f"{path}.{os.getpid()}.tmp"
    with open(tmp, "w") as f:
        json.dump(dialog, f)
    os.replace(tmp, path)
except Exception:
    pass
