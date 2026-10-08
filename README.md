# autopilot

Rebuild my whole Linux setup on any machine with one script. Safe to re-run.

## What it does

1. Detects your distro (Ubuntu/Debian, Arch, Fedora, openSUSE)
2. Syncs the package index and installs bootstrap tools (git, gh, stow, ...)
3. Configures git
4. Creates an SSH key and registers it on GitHub via `gh`
5. Clones my [dotfiles](https://github.com/nullbyte6/dotfiles) and symlinks them with GNU Stow (existing files are backed up to `~/.dotfiles-backup/`)
6. Installs my packages, plus snaps or flatpaks where needed
7. Checks the JetBrains Mono font
8. Installs Steam (with the right GPU libraries on Arch)

## Usage

```bash
git clone https://github.com/nullbyte6/autopilot.git
cd autopilot
./run.sh --dry-run   # preview every change first
./run.sh
```

| Flag | Effect |
|------|--------|
| `-y`, `--yes` | Answer "yes" to package manager prompts |
| `-n`, `--dry-run` | Print every change instead of doing it |
| `--no-steam` | Skip the Steam section |
| `-h`, `--help` | Show help |

## Make it yours

This is built around my setup. Before running it, edit the `Config` block and the package lists at the top of [run.sh](run.sh): git name and email, dotfiles repo, and the packages you want.

## License

[GPL-3.0](LICENSE)
