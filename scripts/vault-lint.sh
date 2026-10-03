#!/usr/bin/env bash
# vault-lint.sh - structural linter for the company brain (report-only).
#
# The directory allowlist is PARSED from the fenced block under
# "## Directory allowlist" in AGENTS.md, so the schema has one source of truth.
# Only the banned-name list and file-type rules live here.
#
# Exit 0 = clean or warnings only, 1 = structural errors, 2 = could not run.
# Usage: bash scripts/vault-lint.sh [--quiet]   (--quiet prints nothing when clean)
# Portable across macOS (BSD date) and Linux/CI (GNU date).
set -uo pipefail

VAULT="$(cd "$(dirname "$0")/.." && pwd)"
SCHEMA="$VAULT/AGENTS.md"
QUIET="${1:-}"
BANNED_ANYWHERE="inbox"
BANNED_WORKSPACE="media misc temp new"
STALE_RAW_DAYS=14
STALE_WIKI_DAYS=180

errors=() ; warnings=()
err()  { errors+=("$1"); }
warn() { warnings+=("$1"); }

[ -f "$SCHEMA" ] || { echo "vault-lint: $SCHEMA missing"; exit 2; }

# portable YYYY-MM-DD -> epoch
to_epoch() { date -d "$1" +%s 2>/dev/null || date -j -f '%Y-%m-%d' "$1" +%s 2>/dev/null; }

# ---- parse the allowlist block from AGENTS.md ------------------------------
allow_block=$(awk '/^## Directory allowlist/{f=1} f&&/^```/{c++; next} c==1{print} c==2{exit}' "$SCHEMA")
[ -n "$allow_block" ] || { echo "vault-lint: could not parse allowlist from $SCHEMA"; exit 2; }

planes=() ; declare -a sub_keys=() sub_vals=()
while IFS= read -r line; do
  [ -z "${line// }" ] && continue
  plane=$(echo "$line" | awk '{print $1}' | sed 's:/*$::')
  rest=$(echo "$line" | awk '{$1=""; sub(/^ +/,""); print}' | tr -d '/')
  planes+=("$plane")
  case "$rest" in *free-form*) rest="__FREE__";; esac
  sub_keys+=("$plane"); sub_vals+=("$rest")
done <<< "$allow_block"

subs_for() { local i; for i in "${!sub_keys[@]}"; do
  [ "${sub_keys[$i]}" = "$1" ] && { echo "${sub_vals[$i]}"; return; }
done; echo ""; }

# ---- 1. vault root: only the known files + allowlisted plane dirs -----------
while IFS= read -r -d '' p; do
  base=$(basename "$p")
  case "$base" in .*) continue;; esac
  if [ -f "$p" ]; then
    case "$base" in AGENTS.md|CLAUDE.md|README.md|index.md) ;; *) err "stray file at vault root: $base";; esac
  else
    case "$base" in scripts) ;; *)
      printf '%s\n' "${planes[@]}" | grep -qx "$base" || err "top-level dir not in allowlist: $base/" ;;
    esac
  fi
done < <(find "$VAULT" -mindepth 1 -maxdepth 1 -print0)

# ---- 2. second level must be allowlisted (free-form planes skipped) ---------
for plane in "${planes[@]}"; do
  [ -d "$VAULT/$plane" ] || { warn "allowlisted plane missing: $plane/"; continue; }
  allowed=$(subs_for "$plane")
  [ "$allowed" = "__FREE__" ] && continue
  while IFS= read -r -d '' d; do
    base=$(basename "$d")
    case "$base" in .*) continue;; esac
    echo "$allowed" | tr -s ' \t' '\n' | grep -qx "$base" \
      || err "$plane/$base/ is not in the allowlist (add it to AGENTS.md first, or refile)"
  done < <(find "$VAULT/$plane" -mindepth 1 -maxdepth 1 -type d -print0)
done

# ---- 3. banned dir names + same-name nesting, any depth --------------------
while IFS= read -r -d '' d; do
  rel=${d#"$VAULT"/}
  # skip dotdirs and the infra scripts/ tree (tooling, not vault content)
  case "$rel" in .*|*/.*|scripts|scripts/*) continue;; esac
  base=$(basename "$d")
  lower=$(echo "$base" | tr '[:upper:]' '[:lower:]')
  for b in $BANNED_ANYWHERE; do
    [ "$lower" = "$b" ] && err "banned directory name '$base' at $rel/"
  done
  case "$rel" in workspace/*)
    for b in $BANNED_WORKSPACE; do
      [ "$lower" = "$b" ] && err "banned directory name '$base' at $rel/ (name workspace folders by stream, not file type)"
    done ;;
  esac
  parent=$(basename "$(dirname "$d")")
  [ "$base" = "$parent" ] && err "same-name nesting: $rel/"
done < <(find "$VAULT" -mindepth 2 -type d -print0)

# ---- 4. sources: .md need status frontmatter; stale raw flagged ------------
if [ -d "$VAULT/sources" ]; then
  while IFS= read -r -d '' f; do
    status=$(awk '/^---$/{c++; next} c==1 && /^status:/{print $2; exit} c>=2{exit}' "$f")
    rel=${f#"$VAULT"/}
    if [ -z "$status" ]; then
      warn "source missing 'status:' frontmatter: $rel"
    elif [ "$status" = "raw" ] && [ -n "$(find "$f" -mtime +"$STALE_RAW_DAYS" 2>/dev/null)" ]; then
      warn "raw source older than ${STALE_RAW_DAYS}d: $rel"
    fi
  done < <(find "$VAULT/sources" -name '*.md' -type f -print0)
fi

# ---- 4b. duplicate title: first H1 repeats the filename --------------------
while IFS= read -r -d '' f; do
  rel=${f#"$VAULT"/}
  case "$rel" in .*|*/.*) continue;; esac
  base=$(basename "$f" .md | tr '[:upper:]' '[:lower:]' | tr -cd 'a-z0-9')
  h1=$(awk '/^---$/{fm++; next} fm==1{next} /^# /{print substr($0,3); exit} NF && !/^#/{exit}' "$f")
  [ -z "$h1" ] && continue
  norm=$(echo "$h1" | tr '[:upper:]' '[:lower:]' | tr -cd 'a-z0-9')
  [ "$norm" = "$base" ] && warn "duplicate title (first H1 repeats the filename): $rel"
done < <(find "$VAULT" -name '*.md' -type f -print0)

# ---- 4c. wiki pages carry 'updated:'; long-untouched pages flagged ---------
if [ -d "$VAULT/wiki" ]; then
  now=$(date +%s)
  while IFS= read -r -d '' f; do
    rel=${f#"$VAULT"/}
    case "$rel" in wiki/_templates/*) continue;; esac
    upd=$(awk '/^---$/{c++; next} c==1 && /^updated:/{sub(/^updated:[[:space:]]*/,""); print $1; exit} c>=2{exit}' "$f" | tr -cd '0-9-')
    if [ -z "$upd" ]; then
      warn "wiki page missing 'updated:' frontmatter: $rel"; continue
    fi
    ts=$(to_epoch "$upd") || { warn "wiki page has unparsable 'updated: $upd': $rel"; continue; }
    [ -z "$ts" ] && { warn "wiki page has unparsable 'updated: $upd': $rel"; continue; }
    age=$(( (now - ts) / 86400 ))
    [ "$age" -gt "$STALE_WIKI_DAYS" ] && warn "wiki page not re-verified in ${age}d (updated: $upd): $rel"
  done < <(find "$VAULT/wiki" -name '*.md' -type f -print0)
fi

# ---- 5. index.md must mention every existing second-level dir --------------
if [ -f "$VAULT/index.md" ]; then
  for plane in "${planes[@]}"; do
    allowed=$(subs_for "$plane")
    { [ "$allowed" = "__FREE__" ] || [ -z "$allowed" ]; } && continue
    for sub in $allowed; do
      [ -d "$VAULT/$plane/$sub" ] || continue
      grep -q "$sub" "$VAULT/index.md" || warn "index.md does not mention $plane/$sub/"
    done
  done
fi

# ---- 6. editor-visibility backstop -----------------------------------------
# 'audience: editors' publishes a page to the editor read site, so it must never
# sit on an internal plane (strategy/client/comp) or a 1:1 / ops meeting.
while IFS= read -r -d '' f; do
  rel=${f#"$VAULT"/}
  grep -qE '^audience:[[:space:]]*editors([[:space:]]|$)' "$f" || continue
  case "$rel" in
    sources/*|wiki/clients/*|wiki/decisions/*)
      err "audience: editors on an internal plane (never expose this): $rel" ;;
    wiki/meetings/*peptalk*|wiki/meetings/*pep-talk*) ;;   # pep-talks may opt in
    wiki/meetings/*)
      err "audience: editors on a non-peptalk meeting (1:1 / ops stay internal): $rel" ;;
  esac
done < <(find "$VAULT/sources" "$VAULT/wiki" -name '*.md' -type f -print0 2>/dev/null)

# ---- 7. handbook boundary: editor pages reference only editor pages --------
# Nothing that is not 'audience: editors' may surface in the handbook. A
# published page may link/embed only other published pages (or pages that do
# not exist yet - those render as plain text); a reference to an EXISTING
# internal page would leak its name or content, so it is an error.
ed_names=""; int_names=""
while IFS= read -r -d '' f; do
  case "${f#"$VAULT"/}" in wiki/_templates/*) continue;; esac
  case "$(basename "$f")" in _*) continue;; esac   # templates are never published
  base=$(basename "$f" .md)
  if grep -qE '^audience:[[:space:]]*editors([[:space:]]|$)' "$f"; then
    ed_names="$ed_names$base"$'\n'
  else
    int_names="$int_names$base"$'\n'
  fi
done < <(find "$VAULT/wiki" "$VAULT/sources" -name '*.md' -type f -print0 2>/dev/null)
is_editor()   { printf '%s' "$ed_names"  | grep -qxF "$1"; }
is_internal() { printf '%s' "$int_names" | grep -qxF "$1"; }

while IFS= read -r -d '' f; do
  rel=${f#"$VAULT"/}
  case "$rel" in wiki/_templates/*) continue;; esac
  case "$(basename "$f")" in _*) continue;; esac   # templates are never published
  grep -qE '^audience:[[:space:]]*editors([[:space:]]|$)' "$f" || continue
  while IFS= read -r m; do
    tgt=${m#!}; tgt=${tgt#\[\[}
    tgt=$(printf '%s' "$tgt" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')
    [ -z "$tgt" ] && continue
    base=$(basename "$tgt")
    if is_internal "$base" && ! is_editor "$base"; then
      err "handbook leak: editor page references internal page: $rel -> [[${tgt}]] (de-link it, or give that page audience: editors)"
    fi
  done < <(grep -oE '!?\[\[[^]|#]+' "$f")
  # markdown links to a vault/.md file or a path escaping the vault are leaks too
  while IFS= read -r m; do
    tgt=${m#](}; tgt=${tgt%)}
    case "$tgt" in http://*|https://*|mailto:*|\#*) continue;; esac
    if printf '%s' "$tgt" | grep -qE '\.md($|#| )|\.\./'; then
      err "handbook leak: editor page markdown-links a vault/internal file: $rel -> ]($tgt) (remove it, or link an editor page with [[...]])"
    fi
  done < <(grep -oE '\]\([^)]+\)' "$f")
done < <(find "$VAULT/wiki" -name '*.md' -type f -print0 2>/dev/null)

# ---- 8. brain agent scripts: shellcheck (best effort; CI is authoritative) --
# scripts/agent runs on every operator machine, so it is gated. CI installs
# shellcheck and fails hard; here we only flag it when shellcheck is present.
if command -v shellcheck >/dev/null 2>&1 && [ -d "$VAULT/scripts/agent" ]; then
  while IFS= read -r -d '' s; do
    shellcheck "$s" >/dev/null 2>&1 || err "shellcheck findings in ${s#"$VAULT"/} (run: shellcheck ${s#"$VAULT"/})"
  done < <(find "$VAULT/scripts/agent" -name '*.sh' -print0)
fi

# ---- report ----------------------------------------------------------------
n_err=${#errors[@]} ; n_warn=${#warnings[@]}
if [ "$n_err" -eq 0 ] && [ "$n_warn" -eq 0 ]; then
  [ "$QUIET" = "--quiet" ] || echo "vault-lint: clean"
  exit 0
fi
if [ "$n_err" -gt 0 ]; then
  echo "vault-lint: $n_err error(s)"
  for e in "${errors[@]}"; do echo "  ERROR: $e"; done
fi
if [ "$n_warn" -gt 0 ]; then
  echo "vault-lint: $n_warn warning(s)"
  for w in "${warnings[@]}"; do echo "  warn:  $w"; done
fi
echo "Rules: AGENTS.md. Errors block; warnings do not."
[ "$n_err" -gt 0 ] && exit 1 || exit 0
