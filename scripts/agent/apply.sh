#!/usr/bin/env bash
# apply.sh - the Aditor brain agent (macOS/Linux).
#
# Applies the desired-state steps declared in manifest.json, idempotently and in
# version order. Each machine records the highest version it has applied in
# ~/.aditor-brain/state.json and only runs newer steps. Every step must be safe
# to re-run. The scheduler (run.sh) calls this after a git pull; you can also run
# it by hand. It never needs sudo; a step that would needs admin rights prints an
# instruction instead.
#
# Kill switch: scripts/agent/DISABLED in the repo stops every machine on the next
# run; ~/.aditor-brain/DISABLED stops this one.
set -uo pipefail

AGENT_DIR="$(cd "$(dirname "$0")" && pwd)"
VAULT="$(cd "$AGENT_DIR/../.." && pwd)"
MANIFEST="$AGENT_DIR/manifest.json"
STATE_DIR="${ADITOR_BRAIN_STATE_DIR:-$HOME/.aditor-brain}"
STATE="$STATE_DIR/state.json"
LOG="$STATE_DIR/agent.log"
LOG_MAX=1048576  # rotate at 1 MB

mkdir -p "$STATE_DIR"

rotate_log() {
  [ -f "$LOG" ] || return 0
  local size
  size=$(wc -c <"$LOG" 2>/dev/null | tr -d ' ')
  [ -n "$size" ] && [ "$size" -gt "$LOG_MAX" ] && mv -f "$LOG" "$LOG.1"
  return 0
}

log() {
  rotate_log
  printf '%s %s\n' "$(date '+%Y-%m-%dT%H:%M:%S')" "$*" >>"$LOG"
  printf '%s\n' "$*" >&2
}

# Minimal, dependency-free JSON reads (integers and a single string field).
json_int() { grep -oE "\"$2\"[[:space:]]*:[[:space:]]*[0-9]+" "$1" 2>/dev/null | head -1 | grep -oE '[0-9]+$'; }

write_state() {
  # write_state <applied_version> <last_error>
  local applied="$1" err="${2:-}"
  printf '{\n  "applied_version": %s,\n  "last_run": "%s",\n  "last_error": "%s"\n}\n' \
    "$applied" "$(date '+%Y-%m-%dT%H:%M:%S')" "$err" >"$STATE"
}

# ---- kill switches ---------------------------------------------------------
if [ -f "$AGENT_DIR/DISABLED" ]; then log "disabled in repo (scripts/agent/DISABLED); skipping"; exit 0; fi
if [ -f "$STATE_DIR/DISABLED" ]; then log "disabled on this machine (~/.aditor-brain/DISABLED); skipping"; exit 0; fi

# ===========================================================================
# Steps. Each is step_<version>, idempotent, returns non-zero only on real
# failure. Add a new step function AND bump manifest.json "version".
# ===========================================================================

# step_1: ensure the Obsidian Git plugin is present so the vault keeps syncing.
# shellcheck disable=SC2317  # dispatched dynamically below as "step_$k"
step_1() {
  local dest="$VAULT/.obsidian/plugins/obsidian-git"
  if [ -f "$dest/main.js" ] && [ -f "$dest/manifest.json" ]; then
    return 0  # already installed
  fi
  command -v gh >/dev/null 2>&1 || { log "step 1: gh not found; cannot fetch the sync plugin (open Obsidian Community Plugins to install it)"; return 1; }
  mkdir -p "$dest"
  local f url ok=1
  for f in main.js manifest.json styles.css; do
    url=$(gh api "repos/Vinzent03/obsidian-git/releases/latest" \
      --jq ".assets[] | select(.name==\"$f\") | .browser_download_url" 2>/dev/null | head -1 || true)
    if [ -n "${url:-}" ]; then
      curl -fsSL "$url" -o "$dest/$f" || { [ "$f" = "styles.css" ] || ok=0; }
    else
      [ "$f" = "styles.css" ] || ok=0
    fi
  done
  if [ "$ok" = "1" ] && [ -f "$dest/main.js" ]; then
    return 0
  fi
  log "step 1: could not install the sync plugin"
  return 1
}

# ---- run newer steps in order ----------------------------------------------
target=$(json_int "$MANIFEST" version)
[ -n "${target:-}" ] || { log "could not read manifest version"; exit 1; }
applied=0
[ -f "$STATE" ] && applied=$(json_int "$STATE" applied_version)
[ -n "${applied:-}" ] || applied=0

if [ "$applied" -ge "$target" ]; then
  log "up to date at version $applied"
  exit 0
fi

k=$((applied + 1))
while [ "$k" -le "$target" ]; do
  if declare -F "step_$k" >/dev/null 2>&1; then
    log "applying step $k"
    if ! "step_$k"; then
      log "step $k failed; staying at version $applied"
      write_state "$applied" "step $k failed"
      exit 1
    fi
  fi
  k=$((k + 1))
done

write_state "$target" ""
log "applied up to version $target"
