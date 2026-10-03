# The Aditor brain agent

A tiny, repo-driven updater that keeps every operator's machine in the state the
company brain declares, after the one-time `bootstrap`. The bootstrap is a
one-shot installer; this is how a change to that setup reaches machines that are
already installed, without anyone re-downloading anything.

## How it works

The repo is already cloned and authenticated on every machine, so the repo is the
distribution channel. A per-user scheduler runs `run.sh` (macOS/Linux) or
`run.ps1` (Windows) at login and every 6 hours. It pulls `main` and runs
`apply.sh` / `apply.ps1`, which applies the steps declared in `manifest.json` in
version order, once each, recording progress in `~/.aditor-brain/state.json`.

To change what every machine does: add a step function (`step_<n>` in `apply.sh`
and `Step-<n>` in `apply.ps1`), bump `manifest.json`'s `version`, open a PR, and
merge. Within 6 hours (or at next login) every machine applies it. Each step must
be idempotent - safe to run again - because a machine may run it more than once.

## Files

| File | Role |
|---|---|
| `manifest.json` | the current desired-state `version` and a human list of steps |
| `apply.sh` / `apply.ps1` | the steps; applies those newer than the machine's state |
| `run.sh` / `run.ps1` | scheduled wrapper: guard, `git pull --ff-only`, then apply |
| `install.sh` / `install.ps1` | install the scheduler (launchd agent / scheduled task) |
| `DISABLED` (create this file) | repo-wide kill switch: stops the agent on every machine |

## Kill switches

- Stop every machine on the next run: `touch scripts/agent/DISABLED`, commit, push.
- Stop one machine: `touch ~/.aditor-brain/DISABLED` (`%USERPROFILE%\.aditor-brain\DISABLED` on Windows).

## Safety

- `run.*` refuses to act unless the checkout is on `main`, has no uncommitted
  changes under `scripts/agent`, and passes `git fsck`. So only reviewed, pushed
  `main` content ever runs.
- The agent never uses sudo. A step needing admin rights prints an instruction.
- Changing these scripts is remote code execution on every operator machine, so
  `scripts/agent` is protected: changes go through a reviewed PR, and CI runs
  `shellcheck` on the shell scripts and a PowerShell parse on the `.ps1` scripts.

## Logs and state

`~/.aditor-brain/agent.log` (rotated at 1 MB) and `~/.aditor-brain/state.json`
(`applied_version`, `last_run`, `last_error`). `launchd` also writes
`launchd.out.log` / `launchd.err.log` there.

## Run it by hand

```
bash scripts/agent/run.sh       # pull + apply (honours the guards)
bash scripts/agent/apply.sh     # apply only, against the current checkout
```
