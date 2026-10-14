#!/usr/bin/env python3
# Checks find_terminal's Ghostty matching: python3 test_find_terminal.py
import server

server.terminal_of = lambda pid: ("ghostty", 1, "")
TABS = [["T1", "✳ Older session", "/a"], ["T2", "✳ Claude Code", "/a"], ["T3", "✳ Claude Code", "/b"]]
server.ghostty_terminals = lambda: TABS


def find(name, titled, cwd="/a"):
    server.scan = lambda: {"sessions": [{"pid": 7, "name": name, "titled": titled, "kind": "interactive", "status": "idle", "cwd": cwd}]}
    return server.find_terminal(7)


assert find("Older session", True)[0][1] == "T1"  # by title
assert find("tmp-ca", False)[0][1] == "T2"  # new session: its folder's one untitled tab
assert find("Renamed", True)[1][0] == 404  # a titled session never takes an untitled tab
TABS.append(["T4", "✳ Claude Code", "/a"])
assert find("tmp-ca", False)[1][0] == 404  # two new sessions in one folder: refused, never a guess
print("find_terminal: 4 checks passed")
