#!/bin/bash
# Aditor Brain - double-click installer (macOS).
#
# How to use:
#   1. Double-click this file.
#   2. If macOS says it is from an unidentified developer, right-click it,
#      choose Open, then click Open in the dialog. (Only the first time.)
#   3. A Terminal window runs the setup. Sign in to GitHub when asked.
#
# This is a thin launcher: it makes sure Homebrew is present, then runs the
# setup script (bootstrap.sh) that ships bundled next to this file in the same
# download. Nothing to type.

set -u

# Where this launcher (and its bundled bootstrap.sh) live.
DIR="$(cd "$(dirname "$0")" && pwd)"

clear 2>/dev/null || true

printf '\n'
printf '  \033[1mAditor Brain\033[0m\n'
printf '  Setting up your shared knowledge vault.\n\n'

# Best-effort: clear the quarantine flag on ourselves so re-runs are quiet.
xattr -d com.apple.quarantine "$0" >/dev/null 2>&1 || true

# --- Homebrew (the package manager the installer needs) -----------------------
BREW=""
for p in /opt/homebrew/bin/brew /usr/local/bin/brew; do
  [ -x "$p" ] && BREW="$p"
done
if [ -z "$BREW" ] && command -v brew >/dev/null 2>&1; then
  BREW="$(command -v brew)"
fi

if [ -z "$BREW" ]; then
  printf '  Installing Homebrew first - you may be asked for your Mac password.\n'
  printf '  This part can take a few minutes on a fresh Mac.\n\n'
  if ! /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"; then
    printf '\n  Homebrew did not finish installing. Close this window and try again,\n'
    printf '  or check the README for help.\n\n'
    printf '  Press Return to close. '
    read -r _ || true
    exit 1
  fi
  for p in /opt/homebrew/bin/brew /usr/local/bin/brew; do
    [ -x "$p" ] && BREW="$p"
  done
fi

# Put brew on PATH for the installer we are about to run.
if [ -n "$BREW" ]; then
  eval "$("$BREW" shellenv)" 2>/dev/null || true
fi

# --- Run the bundled setup script --------------------------------------------
if [ ! -f "$DIR/bootstrap.sh" ]; then
  printf '\n  Could not find bootstrap.sh next to this installer.\n'
  printf '  Keep both files together in the unzipped folder, then try again,\n'
  printf '  or check the README for help.\n\n'
  printf '  Press Return to close. '
  read -r _ || true
  exit 1
fi

printf '\n  Running the setup...\n\n'
if bash "$DIR/bootstrap.sh"; then
  printf '\n  \033[1mAll set.\033[0m You can close this window.\n'
  printf '  Reminder: fully quit Claude Desktop (Cmd+Q) and reopen it.\n'
else
  printf '\n  Something went wrong above. Copy the message and check the README.\n'
fi

printf '\n  Press Return to close. '
read -r _ || true
