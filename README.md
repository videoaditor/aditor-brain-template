# Company Brain

One shared Obsidian vault, in git. Durable, distilled company knowledge - SOPs, checklists, decisions, and reference pages - written by a small core and the agents, read by everyone.

This repo runs on the **Aditor Brain** system: a template plus tooling you spun up for your own company. Git is the source of truth and the backup. There is no server to run.

- The operating law (how it is organised and the rules for writing) is in [`AGENTS.md`](AGENTS.md).
- The map of what is where is in [`index.md`](index.md).

## Spin up your own brain

If you have not created your brain yet, do it from the template in one line - paste this into a terminal, or into Claude Code / Codex and say "run this":

```
curl -fsSL https://raw.githubusercontent.com/videoaditor/aditor-brain-template/main/scripts/bootstrap.sh | bash
```

It installs the tools (Obsidian, git, gh, node), signs you into **your own** GitHub, creates your brain repo from this template, and wires up Obsidian + the self-updating agent + Claude Desktop. Windows: run `scripts/bootstrap.ps1` in PowerShell, or use the `Install-*` download.

## For authors - one-time setup, ~5 minutes

If the brain already exists and you are joining as an author:

1. Install [Obsidian](https://obsidian.md) (the desktop app is free).
2. Clone your brain repo somewhere that is **not** your personal vault:
   ```
   git clone <your-brain-repo-url> ~/company-brain
   ```
3. In Obsidian: **Open folder as vault** -> pick that folder. It opens as a separate vault; your personal notes are untouched.
4. Enable the **Obsidian Git** community plugin (Settings -> Community plugins -> Browse -> "Obsidian Git" -> Install -> Enable). This vault ships its recommended config, so it will auto commit-and-sync and auto-pull once enabled.
5. Authenticate git to GitHub once (SSH key or a GitHub sign-in). After that you just edit; it syncs in the background.

(The one-line install above does all of this for you.)

## For consumers

You do not install anything. You read the generated site in your browser.

## For agents

Read [`AGENTS.md`](AGENTS.md) first - it is the law. Read and write the Markdown files; commit small, one concept at a time; obey the routing table and the closed allowlist. Never touch `.obsidian/` or `.git/`.

## Structure

```
sources/   meetings/ research/ notes/          raw input, immutable
wiki/      sop/ brands/ people/ clients/        the compiled brain (what people read)
           tools/ concepts/ decisions/ _templates/
archive/                                        finished or superseded
```

## Linter

`scripts/vault-lint.sh` checks structure and frontmatter. It runs in CI on every push (reports violations; fails only on structural errors, never on warnings). Run it locally anytime:

```
bash scripts/vault-lint.sh
```

## Publishing the read site

`scripts/build-handbook/build.sh <output_dir>` builds the static read site from the pages marked `audience: editors`. Host that output wherever you like (any static host). German is generated at build time when `ANTHROPIC_API_KEY` is set; without it the build is English-only.

## Keeping the system current

The brain agent (`scripts/agent/`) runs on each author's machine and pulls this repo on a schedule, applying any new setup steps. To pull improvements from the upstream Aditor Brain template, merge them into your repo; your authors' machines pick them up automatically. See `scripts/agent/README.md`.
