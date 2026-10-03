#!/usr/bin/env bash
# run.sh - scheduled entry point for the Aditor brain agent (macOS/Linux).
#
# The launchd agent (ai.aditor.brain-agent.plist) runs this at login and every
# 6 hours. It pulls the repo (the distribution channel) and applies the desired
# state. It refuses to run from an unexpected checkout state so a push to main is
# the only way to change what runs on every machine.
set -uo pipefail

AGENT_DIR="$(cd "$(dirname "$0")" && pwd)"
VAULT="$(cd "$AGENT_DIR/../.." && pwd)"
STATE_DIR="${ADITOR_BRAIN_STATE_DIR:-$HOME/.aditor-brain}"
LOG="$STATE_DIR/agent.log"
mkdir -p "$STATE_DIR"
note() { printf '%s %s\n' "$(date '+%Y-%m-%dT%H:%M:%S')" "$*" >>"$LOG"; }

cd "$VAULT" || { note "run: vault $VAULT missing"; exit 0; }

# Safety: only on main, with no uncommitted changes under the agent dir, and a
# healthy object store. Anything else: skip (fail safe, never apply blindly).
branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "?")
if [ "$branch" != "main" ]; then note "run: not on main ($branch); skipping"; exit 0; fi
if ! git diff --quiet -- scripts/agent 2>/dev/null; then note "run: uncommitted changes under scripts/agent; skipping"; exit 0; fi
if ! git fsck --no-progress --connectivity-only >/dev/null 2>&1; then note "run: git fsck failed; skipping"; exit 0; fi

# Pull the latest (fast-forward only). Obsidian Git usually already did this; this
# covers machines where Obsidian is closed. A non-ff situation is left to Obsidian
# Git to reconcile; we just run the current checkout.
if git pull --ff-only >>"$LOG" 2>&1; then
  note "run: pulled latest"
else
  note "run: git pull --ff-only did not apply (continuing with the current checkout)"
fi

bash "$AGENT_DIR/apply.sh"
