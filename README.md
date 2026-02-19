# jefe

`jefe` is a Bash wrapper for `codex` that adds session discovery, resume menus, live filtering, and maintenance commands.

## Features

- Local-first session resume (same `cwd` first, then global fallback)
- Interactive TUI menu with arrow keys and `j`/`k` navigation
- Live session filtering with `/` (type to filter, `Esc` to clear)
- Old session cleanup (`jefe clean [days]`)
- Defensive terminal recovery on `Ctrl+C`

## Quick Start

### 1. Clone and checkout

```bash
git clone git@github.com:Fur4nk/jefe.git
cd jefe
git checkout main
```

### 2. Install command symlink

Recommended path:

```bash
sudo ln -sf "$(pwd)/jefe.sh" /usr/local/bin/jefe
```

Alternative (less preferred on many systems):

```bash
sudo ln -sf "$(pwd)/jefe.sh" /usr/bin/jefe
```

Then verify:

```bash
jefe --help
```

## Usage

```bash
jefe
jefe clean
jefe clean 90
```

Inside the menu:

- `Up`/`Down` or `k`/`j`: move selection
- `/`: enter live filter mode
- `Backspace`: remove one filter character
- `Ctrl+U`: clear filter
- `Esc`: exit filter mode and clear filter
- `Enter`: resume selected session
- `q`: quit without resuming

## Documentation

- [User Guide](docs/user-guide.md)
- [Implementation Notes](docs/implementation.md)
