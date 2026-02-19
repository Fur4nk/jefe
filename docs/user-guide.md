# User Guide

## Prerequisites

- `codex` in `PATH`
- `jq` in `PATH`
- A terminal (TTY) for interactive menu features

## Command Overview

- `jefe`: open smart resume flow
- `jefe clean [days]`: remove old session files (default: `180`)
- `jefe --help`: show usage

## Smart Resume Flow

1. `jefe` scans `${CODEX_HOME:-$HOME/.codex}/sessions` for `*.jsonl`.
2. It reads `session_meta` from each file.
3. If sessions match current `cwd`, it shows local sessions first.
4. If no local sessions exist, it shows global sessions.
5. You can also choose `New session`.

## Menu Controls

- `Up`/`Down` or `k`/`j`: move selection
- `Enter`: confirm selected item
- `q`: exit menu

### Live Filter (`/`)

- Press `/` to enter filter mode.
- Type any text to filter sessions in real time (case-insensitive substring match).
- `Backspace`: delete one character.
- `Ctrl+U`: clear the entire filter.
- `Esc`: leave filter mode and clear filter.
- If nothing matches, menu shows `No matches`.

## Cleanup Command

`jefe clean [days]`:

- validates numeric input
- previews matched files (up to 12)
- requests explicit confirmation
- removes old `*.jsonl` files and empty directories

## Exit Codes

- `130` on signal interrupt (`Ctrl+C` path)
- non-zero when menu exits without selection
- process is replaced (`exec`) on successful launch/resume
