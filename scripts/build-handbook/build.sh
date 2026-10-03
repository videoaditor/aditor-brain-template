#!/usr/bin/env bash
# Build the editor handbook static site from the vault.
# Usage: build.sh <output_dir>   (output_dir is wiped and rebuilt)
set -euo pipefail

DIR="$(cd "$(dirname "$0")" && pwd)"
VAULT="$(cd "$DIR/../.." && pwd)"
OUT="${1:?usage: build.sh <output_dir>}"

VENV="$DIR/.venv"
if [ ! -x "$VENV/bin/python" ]; then
  python3 -m venv "$VENV"
  "$VENV/bin/pip" install --quiet --disable-pip-version-check markdown
fi

"$VENV/bin/python" "$DIR/build.py" "$OUT" "$VAULT"
