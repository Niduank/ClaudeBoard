#!/bin/bash
#
#  install.sh
#  ClaudeDashboard
#
#  Created by Kévin Naudin on 14/10/2026.
#
#  Installs Claude Dashboard on this Mac: dependencies, the server at login (LaunchAgent), the /sessions-web command,
#  and optionally the page on the tailnet. Safe to run again: it rewrites everything it installed.
#  Usage: ./install.sh              install or reinstall
#         ./install.sh --uninstall  stop the server and remove what the install added
#

set -eo pipefail

REPO="$(cd "$(dirname "$0")" && pwd)"
LABEL=io.github.niduank.claude-dashboard
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
COMMAND="$HOME/.claude/commands/sessions-web.md"
DOMAIN="gui/$(id -u)"
TAILSCALE=/Applications/Tailscale.app/Contents/MacOS/Tailscale
URL=http://localhost:7788
SHORTCUT="$HOME/Desktop/Claude Dashboard.app"
SHORTCUT_ID=io.github.niduank.claude-dashboard.shortcut
SETTINGS="$HOME/.claude/settings.json"

ask() { local a; read -r -p "$1 [y/N] " a || true; [[ $a == [yY]* ]]; }
# true when the Desktop app is the one this script made, so a reinstall or uninstall never touches another app
shortcut_ours() { [[ $(/usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" "$SHORTCUT/Contents/Info.plist" 2>/dev/null) == "$SHORTCUT_ID" ]]; }
xml() { local v="${1//&/&amp;}"; v="${v//</&lt;}"; printf '%s' "${v//>/&gt;}"; }
# add | remove the PermissionRequest hook (board_dialog_hook.py) that lets the page show what an open dialog asks.
# Only our entry is touched; the file is rewritten only when it changes
dialog_hook() {
  "${PYTHON:-python3}" - "$1" "$SETTINGS" "${PYTHON:-python3} $REPO/board_dialog_hook.py" <<'EOF'
import json, os, shutil, sys
mode, path, command = sys.argv[1:]
path = os.path.realpath(path)  # a settings.json linked from a dotfiles repo stays a link
if not os.path.exists(path) and mode == "remove":
    sys.exit()
try:
    settings = json.load(open(path)) if os.path.exists(path) else {}
except (OSError, ValueError):
    settings = None
hooks = settings.get("hooks", {}) if isinstance(settings, dict) else None
if not isinstance(hooks, dict) or not isinstance(hooks.get("PermissionRequest", []), list):
    print(f"- {path} is not in the expected shape: the dialog hook was not {'added' if mode == 'add' else 'removed'}")
    sys.exit()
before = json.dumps(settings)
settings["hooks"] = hooks
groups = []
for group in hooks.get("PermissionRequest", []):
    if not isinstance(group, dict) or not isinstance(group.get("hooks"), list):
        groups.append(group)
        continue
    kept = [h for h in group["hooks"] if not (isinstance(h, dict) and "board_dialog_hook.py" in str(h.get("command", "")))]
    if kept:
        groups.append({**group, "hooks": kept})
if mode == "add":
    groups.append({"matcher": "*", "hooks": [{"type": "command", "command": command, "timeout": 5}]})
if groups:
    hooks["PermissionRequest"] = groups
else:
    hooks.pop("PermissionRequest", None)
if not hooks:
    del settings["hooks"]
if json.dumps(settings) != before:
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path + ".tmp", "w") as f:
        json.dump(settings, f, indent=2, ensure_ascii=False)
        f.write("\n")
    if os.path.exists(path):
        shutil.copymode(path, path + ".tmp")
    os.replace(path + ".tmp", path)
if mode == "add":
    print(f"✓ The page shows what an open dialog asks (permission, question, plan): a hook in {path}")
EOF
}

if [[ ${1:-} == --uninstall ]]; then
  launchctl bootout "$DOMAIN/$LABEL" 2>/dev/null || true
  rm -f "$PLIST" "$COMMAND"
  if shortcut_ours; then rm -rf "$SHORTCUT"; fi
  dialog_hook remove || echo "- The dialog hook stays in $SETTINGS (PermissionRequest, board_dialog_hook.py): remove it by hand"
  rm -rf "$REPO/dialogs"
  echo "Claude Dashboard uninstalled. A tailnet serve set up by the install stays: $TAILSCALE serve --https=443 off"
  exit
fi

[[ $(uname) == Darwin ]] || { echo "Claude Dashboard runs on macOS only." >&2; exit 1; }
# /sessions-web runs the server path unquoted
[[ $REPO != *" "* ]] || { echo "Move the repo to a path without spaces, then run this again." >&2; exit 1; }

# Optional app: installed with Homebrew when the person agrees, else a link
app() {  # name, cask, url, what it is needed for
  if [[ -d "/Applications/$1.app" ]]; then echo "✓ $1"; return; fi
  if command -v brew >/dev/null && ask "$1 is missing ($4). Install it with Homebrew?"; then
    brew install --cask "$2" || echo "- $1 not installed: brew failed"
  else
    echo "- $1 skipped ($4): $3"
  fi
}

echo "== Dependencies"
PYTHON=$(command -v python3 || true)
if [[ -z $PYTHON ]] || ! "$PYTHON" -c 'import sys; sys.exit(sys.version_info < (3, 9))' 2>/dev/null; then
  echo "Python 3.9+ is missing: run xcode-select --install (or brew install python), then this script again." >&2
  exit 1
fi
echo "✓ Python ($PYTHON)"

CLAUDE_BIN=$(command -v claude || true)
[[ -z $CLAUDE_BIN && -x $HOME/.local/bin/claude ]] && CLAUDE_BIN=$HOME/.local/bin/claude
if [[ -z $CLAUDE_BIN ]]; then
  ask "Claude Code is missing. Install it with the official installer?" || { echo "Claude Dashboard needs Claude Code." >&2; exit 1; }
  curl -fsSL https://claude.ai/install.sh | bash
  CLAUDE_BIN=$HOME/.local/bin/claude
fi
echo "✓ Claude Code ($CLAUDE_BIN)"

if [[ -d /Applications/iTerm.app ]]; then
  echo "✓ iTerm2"
  [[ -d /Applications/Ghostty.app ]] && echo "✓ Ghostty"
else
  app Ghostty ghostty https://ghostty.org "open, reply and new session buttons; iTerm2 works too"
fi
app "Google Chrome" google-chrome https://www.google.com/chrome "the page as an app window"
app Tailscale tailscale-app https://tailscale.com/download/mac "access from other devices"

echo
echo "== Project folders"
echo "\"New session\" on the page offers every subfolder of the roots you pick here."
CURRENT=$([[ -f $PLIST ]] && /usr/libexec/PlistBuddy -c "Print :EnvironmentVariables:BOARD_PROJECTS_ROOTS" "$PLIST" 2>/dev/null || true)
# Suggestions: the folders holding the most projects Claude Code has opened
CANDIDATES=()
while IFS= read -r line; do CANDIDATES+=("$line"); done < <("$PYTHON" - <<'EOF'
import collections, json, os
home = os.path.expanduser("~")
try:
    projects = json.load(open(f"{home}/.claude.json")).get("projects", {})
except (OSError, ValueError):
    projects = {}
parents = collections.Counter(os.path.dirname(p) for p in projects if os.path.isdir(p))
for parent, count in parents.most_common(8):
    if count > 1 and parent != home and "/worktrees/" not in parent + "/":
        print(f"{count}\t{parent}")
EOF
)
for i in "${!CANDIDATES[@]}"; do
  printf '  %d) %s  (%s projects)\n' $((i + 1)) "${CANDIDATES[$i]#*$'\t'}" "${CANDIDATES[$i]%%$'\t'*}"
done
if [[ -n $CURRENT ]]; then
  echo "Current: $CURRENT"
  PROMPT="Numbers and/or paths, separated by spaces (Enter keeps the current ones): "
elif (( ${#CANDIDATES[@]} )); then
  PROMPT="Numbers and/or paths, separated by spaces (Enter = 1): "
else
  PROMPT="Paths, separated by spaces (Enter = none): "
fi
read -r -p "$PROMPT" SELECTION || true
if [[ -z $SELECTION ]]; then
  ROOTS=$CURRENT
  [[ -z $ROOTS && ${#CANDIDATES[@]} -gt 0 ]] && ROOTS=${CANDIDATES[0]#*$'\t'}
else
  ROOTS=
  set -f  # a typed * stays a word
  for item in $SELECTION; do
    if [[ $item =~ ^[0-9]+$ ]] && (( item >= 1 && item <= ${#CANDIDATES[@]} )); then
      dir=${CANDIDATES[$((item - 1))]#*$'\t'}
    else
      dir=${item/#\~/$HOME}
      [[ -d $dir ]] || { echo "- $item is not a folder: skipped"; continue; }
      dir=$(cd "$dir" && pwd)
    fi
    ROOTS=${ROOTS:+$ROOTS:}$dir
  done
  set +f
fi
echo "✓ Roots: ${ROOTS:-none}"

echo
echo "== Language"
# The default for the page, the server's messages and the summaries; the page can switch its own texts
CURRENT_LANG=$([[ -f $PLIST ]] && /usr/libexec/PlistBuddy -c "Print :EnvironmentVariables:BOARD_LANG" "$PLIST" 2>/dev/null || true)
if [[ -z $CURRENT_LANG ]]; then
  CURRENT_LANG=en
  # the first preferred language, printed quoted ("fr-FR") or bare (fr)
  first=$(defaults read -g AppleLanguages 2>/dev/null | sed -n 2p)
  first_re='^ *"?fr'
  [[ $first =~ $first_re ]] && CURRENT_LANG=fr
fi
read -r -p "Board language: 1) English 2) Français (Enter = $CURRENT_LANG) " choice || true
case $choice in
  1) BOARD_LANG=en ;;
  2) BOARD_LANG=fr ;;
  *) BOARD_LANG=$CURRENT_LANG ;;
esac
echo "✓ Language: $BOARD_LANG (the page also has an EN / FR switch)"

# The app "New session" opens a tab in; the other actions use each session's own terminal
TERMINAL=ghostty
if [[ -d /Applications/iTerm.app ]]; then
  TERMINAL=iterm
  if [[ -d /Applications/Ghostty.app ]]; then
    CURRENT_TERMINAL=$([[ -f $PLIST ]] && /usr/libexec/PlistBuddy -c "Print :EnvironmentVariables:BOARD_TERMINAL" "$PLIST" 2>/dev/null || true)
    read -r -p "New sessions open in 1) Ghostty or 2) iTerm2? (Enter = ${CURRENT_TERMINAL:-ghostty}) " choice || true
    case $choice in
      1) TERMINAL=ghostty ;;
      2) TERMINAL=iterm ;;
      *) TERMINAL=${CURRENT_TERMINAL:-ghostty} ;;
    esac
  fi
  echo "✓ New sessions open in $TERMINAL"
fi

echo
echo "== Server at login"
mkdir -p "$(dirname "$PLIST")"
cat > "$PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<!-- Written by Claude Dashboard's install.sh. Serves the Claude sessions page on $URL -->
<plist version="1.0">
<dict>
  <key>Label</key><string>$LABEL</string>
  <key>ProgramArguments</key>
  <array>
    <string>$(xml "$PYTHON")</string>
    <string>$(xml "$REPO")/server.py</string>
  </array>
  <key>EnvironmentVariables</key>
  <dict>
    <key>PATH</key><string>$(xml "$(dirname "$CLAUDE_BIN"):$PATH")</string>
    <key>BOARD_PROJECTS_ROOTS</key><string>$(xml "$ROOTS")</string>
    <key>BOARD_TERMINAL</key><string>$TERMINAL</string>
    <key>BOARD_LANG</key><string>$BOARD_LANG</string>
  </dict>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key><true/>
  <key>StandardErrorPath</key><string>$(xml "$REPO")/server.log</string>
</dict>
</plist>
EOF
plutil -lint -s "$PLIST"
launchctl bootout "$DOMAIN/$LABEL" 2>/dev/null || true
# a server started by hand or by /sessions-web would keep the port: the new one could never bind it
for _ in 1 2 3 4 5; do
  lsof -ti tcp:7788 -sTCP:LISTEN >/dev/null || break
  sleep 1
done
if PIDS=$(lsof -ti tcp:7788 -sTCP:LISTEN); then
  echo "Port 7788 is taken by another process ($(echo $PIDS)): stop it (kill $(echo $PIDS)), then run this again." >&2
  exit 1
fi
# bootout returns before the job is gone: bootstrap fails until it is
BOOTED=
for _ in 1 2 3 4 5 6 7 8 9 10; do
  launchctl bootstrap "$DOMAIN" "$PLIST" 2>/dev/null && { BOOTED=1; break; }
  sleep 1
done
[[ -n $BOOTED ]] || { echo "launchctl bootstrap failed: launchctl bootstrap $DOMAIN $PLIST shows why." >&2; exit 1; }
for _ in 1 2 3 4 5 6 7 8 9 10; do
  curl -fs -o /dev/null "$URL" && break
  sleep 1
done
curl -fs -o /dev/null "$URL" || { echo "The server did not start: see $REPO/server.log" >&2; exit 1; }
echo "✓ Serving $URL (restarted at login and if it stops)"

mkdir -p "$(dirname "$COMMAND")"
REPO_SED=$(printf '%s' "$REPO" | sed 's/[#&\\]/\\&/g')
sed "s#__REPO__#$REPO_SED#g" "$REPO/install/sessions-web.md" > "$COMMAND"
echo "✓ /sessions-web opens the page from any Claude Code session"

dialog_hook add || echo "- The dialog hook was not added: the page shows only the kind of an open dialog"

# Built aside then moved in one step: Finder never caches the icon of a half-made bundle
make_shortcut() {
  local tmp
  tmp=$(mktemp -d "$HOME/Desktop/.ClaudeDashboard.XXXXXX") &&
  mkdir -p "$tmp/Contents/MacOS" "$tmp/Contents/Resources" &&
  cp "$REPO/assets/ClaudeDashboard.icns" "$tmp/Contents/Resources/" &&
  printf '#!/bin/sh\nexec "%s" "%s/server.py" --open\n' "$PYTHON" "$REPO" > "$tmp/Contents/MacOS/ClaudeDashboard" &&
  chmod +x "$tmp/Contents/MacOS/ClaudeDashboard" && chmod 755 "$tmp" &&
  cat > "$tmp/Contents/Info.plist" <<EOF &&
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleIdentifier</key><string>$SHORTCUT_ID</string>
  <key>CFBundleName</key><string>Claude Dashboard</string>
  <key>CFBundleExecutable</key><string>ClaudeDashboard</string>
  <key>CFBundleIconFile</key><string>ClaudeDashboard</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>LSUIElement</key><true/>
</dict>
</plist>
EOF
  rm -rf "$SHORTCUT" && mv "$tmp" "$SHORTCUT"
}
if [[ -e $SHORTCUT ]] && ! shortcut_ours; then
  echo "- $SHORTCUT is another app: Desktop shortcut skipped"
elif [[ -e $SHORTCUT ]] || ask "Add a Claude Dashboard shortcut to the Desktop?"; then
  if make_shortcut; then
    echo "✓ Desktop shortcut: Claude Dashboard opens the page"
  else
    rm -rf "$HOME"/Desktop/.ClaudeDashboard.?????? 2>/dev/null || true
    echo "- Desktop shortcut not written (is the Desktop folder allowed for this terminal?)"
  fi
fi

if [[ -x $TAILSCALE ]] && ask "Serve the page on your tailnet (HTTPS, your devices only)?"; then
  echo
  echo "== Tailscale"
  until "$TAILSCALE" status >/dev/null 2>&1; do
    open -g -a Tailscale
    read -r -p "Log in to Tailscale (menu bar icon), then press Enter. " _ || exit 1
  done
  # the server accepts the tailnet name only for this login (the app's CLI does not answer under launchd)
  "$TAILSCALE" status --json | "$PYTHON" -c "import json, sys
d = json.load(sys.stdin); me = d['Self']
json.dump({'host': me['DNSName'].rstrip('.'), 'login': d['User'][str(me['UserID'])]['LoginName']}, open(sys.argv[1], 'w'))" "$REPO/tailnet.json"
  echo "If Tailscale asks to enable HTTPS or Serve on the tailnet, follow its link."
  "$TAILSCALE" serve --bg http://127.0.0.1:7788
  echo "✓ https://$("$PYTHON" -c "import json, sys; print(json.load(open(sys.argv[1]))['host'])" "$REPO/tailnet.json")"
  echo "  It needs MagicDNS and HTTPS certificates on the tailnet (Tailscale admin console > DNS)."
fi

echo
echo "Done. The first click that drives Ghostty or iTerm2 asks to let python3 control it: allow it."
