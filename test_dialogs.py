#!/usr/bin/env python3
#  Checks for answering Claude Code dialogs from the board: python3 test_dialogs.py
import json
import os
import tempfile

import server

FIND_TERMINAL = server.find_terminal  # fake_board replaces it


def question(*specs):
    """specs: number of options, or (number of options, multiSelect)"""
    specs = [s if isinstance(s, tuple) else (s, False) for s in specs]
    return {"tool": "AskUserQuestion", "at": 1, "questions": [
        {"question": f"Q{n}", "multiSelect": multi, "options": [f"o{i}" for i in range(count)]}
        for n, (count, multi) in enumerate(specs)]}


def raises(dialog, answer):
    try:
        server.keys_for(dialog, answer)
    except ValueError:
        return True
    return False


def test_keys_question():
    assert server.keys_for(question(3), {"choices": [[1]]}) == [("choice", "2")]
    assert server.keys_for(question(3, 3), {"choices": [[0], [2]]}) == [("choice", "1"), ("choice", "3"), ("choice", "1")]
    assert server.keys_for(question((3, True)), {"choices": [[0, 2]]}) == \
        [("choice", "1"), ("choice", "3"), ("key", "arrowRight"), ("choice", "1")]


def test_keys_permission_and_plan():
    for tool in ("Bash", "ExitPlanMode"):
        dialog = {"tool": tool, "at": 1, "detail": "x"}
        assert server.keys_for(dialog, {"decision": "allow"}) == [("choice", "1")]
        assert server.keys_for(dialog, {"decision": "deny"}) == [("key", "escape")]
        assert raises(dialog, {"decision": "always"})


def test_keys_invalid():
    assert raises(question(2), {"choices": []})
    assert raises(question(2, 2), {"choices": [[0]]})
    assert raises(question(2), {"choices": [[2]]})
    assert raises(question(2), {"choices": [[-1]]})
    assert raises(question(2), {"choices": [[True]]})
    assert raises(question((3, True)), {"choices": [[1, 1]]})
    assert raises(question((3, True)), {"choices": [[]]})
    assert raises(question(2), {"choices": [[0, 1]]})
    assert raises(question(2), {"choices": [0]})
    assert raises(question(0), {"choices": [[0]]})
    assert raises(question(9), {"choices": [[0]]})
    assert raises({"tool": "AskUserQuestion", "at": 1, "questions": []}, {"choices": []})
    assert raises(question(2), "nope")
    assert raises({"tool": "Bash", "at": 1}, ["allow"])


def fake_board(dialog):
    """Replaces the scan, the terminal lookup and osascript; returns the list the osascript calls land in."""
    calls = []
    server._answered.clear()
    server.scan = lambda: {"sessions": [{"pid": 7, "sessionId": "s1", "dialog": dialog}]}
    server.find_terminal = lambda pid, send=False: (("ghostty", "T1", True), None)
    server.osascript = lambda script, *args: calls.append((script, args)) or type("Done", (), {"returncode": 0})()
    return calls


def test_answer_ghostty_keys():
    calls = fake_board(question(3, (3, True)))
    assert server.answer(7, 1, {"choices": [[0], [2]]}) == (200, ("answered", {}))
    assert calls == [(server.KEYS["ghostty"], ("T1", "numpad1", "numpad3", "arrowRight", "numpad1"))]
    calls = fake_board({"tool": "Bash", "at": 1, "detail": "ls"})
    assert server.answer(7, 1, {"decision": "deny"})[0] == 200
    assert calls == [(server.KEYS["ghostty"], ("T1", "escape"))]


def test_answer_iterm_text():
    calls = fake_board(question((3, True)))
    server.find_terminal = lambda pid, send=False: (("iterm", "/dev/ttys001", True), None)
    assert server.answer(7, 1, {"choices": [[0]]})[0] == 200
    assert calls == [(server.KEYS["iterm"], ("/dev/ttys001", "1", "\x1b[C", "1"))]
    calls = fake_board({"tool": "Bash", "at": 1, "detail": "ls"})
    server.find_terminal = lambda pid, send=False: (("iterm", "/dev/ttys001", True), None)
    server.answer(7, 1, {"decision": "deny"})
    assert calls == [(server.KEYS["iterm"], ("/dev/ttys001", "\x1b"))]


def test_answer_stale_or_twice():
    calls = fake_board(question(2))
    assert server.answer(7, 2, {"choices": [[1]]}) == (409, ("answer_changed", {}))
    assert server.answer(7, 1, {"choices": [[1]]})[0] == 200
    # the status has not moved yet: the same dialog is still open, but already answered
    assert server.answer(7, 1, {"choices": [[0]]})[0] == 409
    assert len(calls) == 1
    calls = fake_board(None)
    assert server.answer(7, 1, {"choices": [[1]]})[0] == 409
    assert server.answer(8, 1, {"choices": [[1]]}) == (404, ("not_found", {}))
    assert calls == []


def test_answer_invalid_types_nothing():
    calls = fake_board(question(2))
    assert server.answer(7, 1, {"choices": [[True]]}) == (400, ("bad_answer", {}))
    assert server.answer(7, 1, "x")[0] == 400
    assert calls == []


def test_answer_refused():
    fake_board(question(2))
    server.osascript = lambda script, *args: type("Done", (), {"returncode": 1})()
    assert server.answer(7, 1, {"choices": [[0]]}) == (500, ("answer_refused", {"app": "Ghostty"}))
    # a refused answer may be retried
    assert server.answer(7, 1, {"choices": [[0]]})[0] == 500


def test_find_terminal_ghostty():
    server.scan = lambda: {"sessions": [{"pid": 7, "name": "s", "kind": "interactive", "status": "idle", "cwd": "/a"}]}
    server.terminal_of = lambda pid: ("ghostty", 1, "")
    server.ghostty_terminals = lambda: [["T1", "✳ s", "/b"], ["T2", "✳ s", "/c"]]
    assert FIND_TERMINAL(7) == (None, (409, ("ghostty_ambiguous", {})))
    # same title twice, but only one of them in the session's folder
    server.ghostty_terminals = lambda: [["T1", "✳ s", "/a"], ["T2", "✳ s", "/b"], ["T3", "x", "/z"]]
    assert FIND_TERMINAL(7) == (("ghostty", "T1", False), None)
    server.ghostty_terminals = lambda: [["T1", "✳ s", "/b"], ["T2", "✳ s", "/b"], ["T3", "x", "/a"]]
    assert FIND_TERMINAL(7)[1][0] == 409
    server.ghostty_terminals = lambda: [["T1", "✳ s", "/a"], ["T2", "✳ other", "/b"]]
    assert FIND_TERMINAL(7) == (("ghostty", "T1", False), None)


def test_open_dialog_at():
    server.HERE = tempfile.mkdtemp()
    os.mkdir(f"{server.HERE}/dialogs")
    for tool, args in (("Bash", {"command": "ls"}), ("ExitPlanMode", {"plan": "# P"}),
                       ("AskUserQuestion", {"questions": [{"question": "Q", "options": [{"label": "a"}]}]})):
        json.dump({"tool": tool, "input": args, "at": 1234}, open(f"{server.HERE}/dialogs/s1.json", "w"))
        dialog = server.open_dialog("s1", 1234)
        assert dialog["at"] == 1234 and dialog["tool"] == tool


if __name__ == "__main__":
    tests = [f for name, f in sorted(globals().items()) if name.startswith("test_")]
    for test in tests:
        test()
    print(f"{len(tests)} checks passed")
