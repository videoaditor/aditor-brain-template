#!/usr/bin/env bash
# install.sh - install the Aditor brain agent as a launchd agent (macOS).
#
# Writes ~/Library/LaunchAgents/ai.aditor.brain-agent.plist pointing at this
# checkout's run.sh, then loads it. Idempotent: re-running refreshes the plist.
# Called once by bootstrap.sh; safe to run again. Linux is not a target (authors
# use macOS and Windows); on Linux this prints a note and exits 0.
set -uo pipefail

AGENT_DIR="$(cd "$(dirname "$0")" && pwd)"
RUN="$AGENT_DIR/run.sh"
LABEL="ai.aditor.brain-agent"

if [ "$(uname -s)" != "Darwin" ]; then
  echo "brain agent: launchd install is macOS only; on Linux schedule $RUN every 6h via cron or a systemd --user timer."
  exit 0
fi

PLIST_DIR="$HOME/Library/LaunchAgents"
PLIST="$PLIST_DIR/$LABEL.plist"
mkdir -p "$PLIST_DIR"

cat >"$PLIST" <<PLISTEOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>$LABEL</string>
  <key>ProgramArguments</key>
  <array>
    <string>/bin/bash</string>
    <string>$RUN</string>
  </array>
  <key>RunAtLoad</key><true/>
  <key>StartInterval</key><integer>21600</integer>
  <key>ProcessType</key><string>Background</string>
  <key>StandardOutPath</key><string>$HOME/.aditor-brain/launchd.out.log</string>
  <key>StandardErrorPath</key><string>$HOME/.aditor-brain/launchd.err.log</string>
</dict>
</plist>
PLISTEOF

mkdir -p "$HOME/.aditor-brain"
# Reload so changes take effect; bootstrap-mode uses the modern bootstrap/kickstart
# verbs when available, falling back to load/unload on older macOS.
uid=$(id -u)
if launchctl bootstrap "gui/$uid" "$PLIST" 2>/dev/null; then
  launchctl kickstart -k "gui/$uid/$LABEL" 2>/dev/null || true
else
  launchctl unload "$PLIST" 2>/dev/null || true
  launchctl load "$PLIST" 2>/dev/null || true
fi

echo "brain agent installed: $LABEL (runs $RUN at login and every 6h)."
