# Implementation Notes

## File Layout

- `jefe.sh`: single-file implementation (entrypoint, parsing, TUI, cleanup)

## Data Source

Sessions are read from:

```bash
${CODEX_HOME:-$HOME/.codex}/sessions
```

The script parses first line metadata with `jq` and extracts:

- `payload.timestamp`
- `payload.id`
- `payload.cwd`
- `payload.cli_version`

## Selection Model

- Records are sorted by timestamp (descending).
- Local rows are derived by normalized `cwd` match.
- If local rows are empty, global unique sessions are shown.

## TUI Rendering

- Uses `tput smcup/rmcup` for alternate screen.
- Uses `tput civis/cnorm` for cursor visibility.
- Width-aware labels avoid wrapping flicker.
- Incremental redraw updates only changed rows unless page offset changes.

## Filter Engine

Filter mode starts with `/` and operates on menu labels:

- ANSI color codes are stripped before matching.
- Matching is case-insensitive substring.
- Filtered list keeps an index map back to original item positions.
- Selection returns original index via `REPLY`.

This preserves existing business logic while enabling dynamic filtering.

## Signal and TTY Safety

- Global traps handle `EXIT`, `INT`, `TERM`, `HUP`.
- Cleanup restores cursor and screen buffer if active.
- `stty sane` is used on interrupt/read-failure paths.

Goal: prevent hidden cursor and broken terminal state after abrupt exits.
