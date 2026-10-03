# Company Brain - operating law

This repository IS your company brain: one Obsidian vault of durable, distilled knowledge - SOPs, checklists, decisions, and the reference pages your team and the agents rely on.
It is plain Markdown in git.
It runs on the **Aditor Brain** system - a template plus tooling you spin up for your own company and keep current from upstream.
Everyone reads it; a small core writes it; the agents read and write it too.

This file is the law.
It is tool-agnostic - Claude Code also reads `CLAUDE.md`, which just points here.
Read it before you write anything into the vault.

## How to use this vault

- **Authors (a small core):** open this folder as a vault in Obsidian and edit normally. The Obsidian Git plugin commits and pushes for you. One-time setup is in `README.md`. After setup, the brain agent (`scripts/agent/`) keeps your tooling current from the repo.
- **Agents:** you may read and write. Commit small, one concept at a time. Obey the routing table and the closed allowlist below. Never touch `.obsidian/` or `.git/`.
- **Consumers (the wider team):** read the generated site. Do not edit here.

`scripts/agent/` runs on every operator machine, so a change there is remote code execution across the team: it goes through a reviewed PR, CI shellchecks and parses it, and it only ever runs committed `main`. See `scripts/agent/README.md`.

## Planes

One question decides where a file goes: what lifecycle stage is it in?

- `sources/` - immutable raw input (meeting transcripts, captures, notes). Never edit a source after saving it.
- `wiki/` - the compiled brain: distilled, cross-linked pages. This is what people read.
- `archive/` - finished or superseded. Nothing here is current.
- `index.md` - the map. Read it first; keep it current.

## Routing table

| Artifact | Destination |
|---|---|
| Meeting transcript / call notes | `sources/meetings/YYYY-MM-DD-slug.md` |
| External capture (article, scrape, transcript) | `sources/research/` |
| A fleeting note or insight | `sources/notes/YYYY-MM-DD-slug.md` |
| An SOP / how-to the team follows | `wiki/sop/` |
| A per-brand or per-product checklist | `wiki/brands/` |
| A person we work with | `wiki/people/` |
| A client / account overview | `wiki/clients/` |
| A tool / system reference | `wiki/tools/` |
| A concept / framework | `wiki/concepts/` |
| A decision + its reasoning | `wiki/decisions/` |
| A meeting summary (distilled) | `wiki/meetings/YYYY-MM-DD-slug.md` |
| A page template | `wiki/_templates/` |
| Finished or superseded work | `archive/` |

If an artifact fits no row, do not invent a folder: add a row and an allowlist entry below first, in the same change, then file it.

## Directory allowlist (closed)

```
sources/     meetings/ research/ notes/
wiki/        people/ clients/ tools/ concepts/ decisions/ sop/ brands/ meetings/ _templates/
archive/     (free-form below the top level)
```

`scripts/vault-lint.sh` parses this block, so it is the one source of truth for the schema.
The linter runs in CI on every push: it reports violations and fails only on structural errors (a stray root file, a directory not in the allowlist). Warnings (missing `updated:`, a stale page) never block.

## Rules

- **One concept, one page.** When new info conflicts with a page, update it and note what changed; never duplicate.
- **Cross-link aggressively** with `[[page name]]`. A link to a page that does not exist yet is fine - it marks a gap worth filling.
- **No secrets.** Never write credentials, tokens, passwords, or server addresses here. If you find one, remove it and point to the `.env` that owns it.
- **No live state.** Do not paste IDs, statuses, or record values that change on their own. Link to the system of record (your task board, your database) instead.
- **Ground every fact.** Trace each claim to a `sources/` file or a dated "confirmed with <name>" note. Mark anything unverified as unverified, never as fact.
- **Filename is the title.** Obsidian renders the filename as the page title. Do not start a page with an H1 that repeats it; begin with content and use `##` headings.
- **Keep the map current.** After adding or moving pages, update `index.md`.
- **Bump `updated:`** only after re-reading a page against its sources. It is the only decay signal the vault has.

## Frontmatter

Source files (`sources/`), saved once and never edited:

```
---
title:
url:                # if it came from a URL
captured: YYYY-MM-DD
type: article | transcript | note | capture
status: raw | processed
---
```

Wiki pages (`wiki/`), compiled from sources - distil, do not paste:

```
---
title:
summary:            # one sentence; this is the queryable hook
tags: []
type: person | client | tool | concept | decision | sop | brand | framework | meeting
audience: editors   # OPTIONAL. Add this one line to publish the page to the read site. Omit it and the page stays internal. See "Published visibility".
owner:              # who maintains this page
created: YYYY-MM-DD
updated: YYYY-MM-DD
sources: []         # the sources/ files this was compiled from
---

## Content

## Related
- [[other page]]
```

`wiki/_templates/` holds the blank templates and is exempt from the frontmatter checks.

## Published visibility

The brain is internal by default. A separate read site publishes the subset meant for the wider team, and it is **default-deny**: a page reaches the site ONLY if its frontmatter carries `audience: editors`. Omit the field and the page stays internal - so a new page is never exposed by accident.

A good default: publish all of `wiki/sop/`, all of `wiki/brands/`, the team-facing pages under `wiki/tools/`, and a `wiki/people/team.md` names-and-roles who's-who. Opt specific meeting pages in only when they are all-hands material. Decide this per page for your own org.

Never put `audience: editors` on anything under `sources/`, `wiki/clients/`, `wiki/decisions/`, or on a 1:1 / ops meeting page - these hold strategy, client, comp, and leadership detail. The linter enforces this and fails the build if the flag appears there.

A published page may link or embed **only** other published pages (or pages that do not exist yet). A `[[link]]` to an existing internal page would drag its name or content into the read site, so the linter fails the build on it - de-link it to plain text, or give the target `audience: editors` if it truly belongs there.
