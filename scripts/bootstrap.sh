#!/usr/bin/env bash
# Aditor Brain - one-shot setup for your own company brain (macOS).
#
# Spins up YOUR brain from the public template: installs the tools, signs you in
# to YOUR GitHub, creates your brain repo from the template, and wires up
# Obsidian + the self-updating agent + Claude Desktop. Nothing is shared with
# anyone else's brain.
#
# Run it directly:  curl -fsSL https://raw.githubusercontent.com/videoaditor/aditor-brain-template/main/scripts/bootstrap.sh | bash
# Or it ships bundled inside the Install-Aditor-Brain download and is run by the
# double-click launcher (Install-Aditor-Brain.command).
# Idempotent: safe to re-run; it updates instead of duplicating.
set -euo pipefail

TEMPLATE="videoaditor/aditor-brain-template"       # the public template to create from
NAME="${ADITOR_BRAIN_NAME:-company-brain}"          # the repo name created in YOUR account
DEST="${ADITOR_VAULT_DIR:-$HOME/$NAME}"             # where it is cloned locally
VISIBILITY="${ADITOR_BRAIN_VISIBILITY:-private}"    # private (default) or public
PLUGIN_REPO="Vinzent03/obsidian-git"
PLUGDIR="$DEST/.obsidian/plugins/obsidian-git"

say() { printf '\n\033[1m==> %s\033[0m\n' "$1"; }

say "Aditor Brain setup"

# 1. Homebrew (package manager)
if ! command -v brew >/dev/null 2>&1; then
  echo "Homebrew is required. Install it from https://brew.sh then re-run this." >&2
  exit 1
fi

# 2. Obsidian + git + gh + node
say "Checking tools (Obsidian, git, gh, node)"
brew list --cask obsidian >/dev/null 2>&1 || brew install --cask obsidian
command -v git  >/dev/null 2>&1 || brew install git
command -v gh   >/dev/null 2>&1 || brew install gh
command -v node >/dev/null 2>&1 || brew install node   # needed for Claude Desktop's filesystem access

# 3. GitHub sign-in with YOUR OWN account - only if not already signed in
if ! gh auth status >/dev/null 2>&1; then
  say "Sign in to GitHub with your own account"
  gh auth login -h github.com -p https -w
fi
LOGIN="$(gh api user --jq .login)"

# 4. Get your brain: clone it if it already exists, otherwise create it from the
#    template into your own account. Fully idempotent.
if [ -d "$DEST/.git" ]; then
  say "Brain already here - pulling the latest"
  git -C "$DEST" pull --rebase --autostash || true
elif gh repo view "$LOGIN/$NAME" >/dev/null 2>&1; then
  say "Your brain repo exists ($LOGIN/$NAME) - cloning it to $DEST"
  gh repo clone "$LOGIN/$NAME" "$DEST"
else
  say "Creating your brain from the template -> $LOGIN/$NAME"
  gh repo create "$NAME" --template "$TEMPLATE" --"$VISIBILITY"
  # The template copy is ready on GitHub; clone it to $DEST. Retry briefly, as a
  # fresh template copy can take a moment to become cloneable.
  for _ in 1 2 3 4 5; do
    gh repo clone "$LOGIN/$NAME" "$DEST" && break
    sleep 2
  done
fi
[ -d "$DEST/.git" ] || { echo "Could not set up the brain at $DEST" >&2; exit 1; }

# 5. Install the Obsidian Git plugin (latest release) into the vault
say "Installing the sync plugin (Obsidian Git)"
mkdir -p "$PLUGDIR"
for f in main.js manifest.json styles.css; do
  url=$(gh api "repos/$PLUGIN_REPO/releases/latest" \
        --jq ".assets[] | select(.name==\"$f\") | .browser_download_url" 2>/dev/null | head -1 || true)
  if [ -n "${url:-}" ]; then
    curl -fsSL "$url" -o "$PLUGDIR/$f" || echo "  (could not fetch $f - Obsidian can install the plugin from Community Plugins instead)"
  fi
done
# the vault already ships community-plugins.json + the plugin's data.json, so it auto-enables and auto-syncs

# 6. Point Claude Desktop at the vault (filesystem MCP) - merged into any existing config
say "Configuring Claude Desktop file access"
CFG_DIR="$HOME/Library/Application Support/Claude"
mkdir -p "$CFG_DIR"
if command -v npx >/dev/null 2>&1; then
  python3 - "$CFG_DIR/claude_desktop_config.json" "$DEST" <<'PY'
import json, sys
cfg_path, vault = sys.argv[1], sys.argv[2]
try:
    cfg = json.load(open(cfg_path))
    if not isinstance(cfg, dict): cfg = {}
except Exception:
    cfg = {}
servers = cfg.setdefault("mcpServers", {})
fs = servers.get("filesystem")
if isinstance(fs, dict) and isinstance(fs.get("args"), list):
    if vault not in fs["args"]:
        fs["args"].append(vault)          # keep any folders already allowed
    fs.setdefault("command", "npx")
else:
    servers["filesystem"] = {"command": "npx",
        "args": ["-y", "@modelcontextprotocol/server-filesystem", vault]}
json.dump(cfg, open(cfg_path, "w"), indent=2)
print("  wrote", cfg_path)
PY
else
  echo "  Node/npx not found - skipped. Add the folder later in Claude Desktop: Settings -> Developer -> Edit Config."
fi

# 6b. Install the brain agent: keeps this setup current after install, so a
# change pushed to the repo reaches this machine within 6 hours.
say "Installing the brain agent (keeps your setup up to date)"
bash "$DEST/scripts/agent/install.sh" || echo "  (brain agent install skipped)"
bash "$DEST/scripts/agent/run.sh" >/dev/null 2>&1 || true

# 7. Open Obsidian on the vault
say "Opening Obsidian"
if command -v python3 >/dev/null 2>&1; then
  enc=$(python3 -c 'import urllib.parse,sys;print(urllib.parse.quote(sys.argv[1]))' "$DEST")
  open "obsidian://open?path=$enc" 2>/dev/null || open -a Obsidian "$DEST" 2>/dev/null || true
else
  open -a Obsidian "$DEST" 2>/dev/null || true
fi

cat <<EOF

Done.

Your brain:  $LOGIN/$NAME  (cloned to $DEST)

Obsidian: should open the vault at $DEST (confirm "Open as vault" if asked).
Your edits sync to GitHub automatically every few minutes.

Claude Desktop: fully quit it (Cmd+Q) and reopen so it picks up the vault.
It can then read and write your notes (it asks permission per file).

Prefer Claude Code? Just point it at $DEST - it reads the law (AGENTS.md) on its own.
EOF
