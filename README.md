# jefe

`jefe` is a Bash wrapper around the `codex` CLI that adds smart session discovery, interactive resume selection, and maintenance tools.

## What `jefe` does

- Launches `codex` normally when no reusable session is found.
- Scans Codex session metadata under `${CODEX_HOME:-$HOME/.codex}/sessions`.
- Detects sessions created from the current working directory and prioritizes them.
- Opens an interactive terminal menu to resume a session or start a new one.
- Falls back to global session selection when no local (same-cwd) session exists.
- Provides a cleanup command to remove old session files:
  - `jefe clean [days]` (default: `180`)

## How it works

### 1. Dependency and environment checks

At startup, `jefe` validates required tools:

- `codex` must be available in `PATH`
- `jq` must be available in `PATH`

It also resolves:

- session root: `SESSIONS_ROOT="${CODEX_HOME:-$HOME/.codex}/sessions"`
- terminal width/colors (via `tput`) when running in a TTY

### 2. Session discovery and parsing

`jefe` searches for `*.jsonl` files in the sessions root and reads the first line of each file.  
It extracts session metadata with `jq` only when the line is a valid `session_meta` record:

- `payload.timestamp`
- `payload.id`
- `payload.cwd`
- `payload.cli_version`

Records are sorted by timestamp (newest first).

### 3. Smart local-first resume

`jefe` normalizes paths and compares each session `cwd` with the current directory:

- If matching sessions exist:
  - show local sessions menu
  - include a `New session` option
- If no local sessions exist:
  - show a global sessions menu

Selection behavior:

- `Enter` resumes selected session
- selecting `New session` starts plain `codex`
- `q` exits without launching

### 4. Interactive menu rendering

The menu uses terminal control (`tput`) with an alternate screen and hidden cursor:

- `smcup` / `rmcup` for alternate screen buffer
- `civis` / `cnorm` for cursor visibility

Navigation:

- Arrow keys (`Up`/`Down`)
- Vim-style keys (`k`/`j`)

To reduce flicker:

- labels are width-aware and truncated to fit terminal columns
- full redraw happens only when page offset changes
- otherwise only the previously selected row and current row are redrawn

### 5. Terminal safety on interrupts

`jefe` includes defensive cleanup for interrupted TUI flows:

- global traps for `EXIT`, `INT`, `TERM`, `HUP`
- always restores cursor and exits alternate screen if active
- runs `stty sane` on interrupt/read-failure paths to recover broken TTY state

This prevents the common "hidden cursor after Ctrl+C" problem.

### 6. Cleanup command

`jefe clean [days]`:

- validates `days` as numeric
- finds old `*.jsonl` sessions older than `days`
- shows a preview (first 12 paths)
- asks for explicit confirmation
- deletes selected files
- removes empty directories under sessions root

## Usage

```bash
jefe
jefe clean
jefe clean 90
```

## Exit behavior

- Returns `130` on signal interrupt (`Ctrl+C` path).
- Returns non-zero when user exits the menu (`q`) without selecting.
- Otherwise replaces process via `exec codex ...` / `exec codex resume ...`.

## Notes

- `jefe` is intentionally a single-file script for portability and easy patching.
- It does not modify Codex session contents; it only reads metadata and dispatches `codex` commands.
