#!/usr/bin/env bash
set -uo pipefail

KEEP_VERSIONS=1
JOURNAL_MAX=100M
PROTECTED=(qt6-wayland)
ASSUME_YES=0
[[ "${1:-}" == "--yes" || "${1:-}" == "-y" ]] && ASSUME_YES=1

if [[ $EUID -ne 0 ]]; then
    exec sudo -E bash "$0" "$@"
fi

REAL_USER="${SUDO_USER:-root}"
REAL_HOME="$(getent passwd "$REAL_USER" | cut -d: -f6)"

used() { df -B1 --output=used / | tail -1 | tr -d ' '; }
human() { numfmt --to=iec --suffix=B "$1"; }
step() { printf '\n\033[1;34m==> %s\033[0m\n' "$1"; }
confirm() {
    [[ $ASSUME_YES -eq 1 ]] && return 0
    read -r -p "$1 [y/N] " reply
    [[ "$reply" =~ ^[Yy]$ ]]
}

before=$(used)

step "Pacman cache (keeping $KEEP_VERSIONS version per package)"
if command -v paccache >/dev/null; then
    paccache -rk"$KEEP_VERSIONS"
    paccache -ruk0
else
    echo "paccache missing: sudo pacman -S pacman-contrib"
fi

step "Orphaned packages"
mapfile -t orphans < <(pacman -Qdtq 2>/dev/null)
filtered=()
for p in "${orphans[@]}"; do
    skip=0
    for k in "${PROTECTED[@]}"; do [[ "$p" == "$k" ]] && skip=1; done
    [[ $skip -eq 0 ]] && filtered+=("$p")
done
if ((${#filtered[@]})); then
    printf '  %s\n' "${filtered[@]}"
    if confirm "Remove these ${#filtered[@]} orphans (with configs and unneeded deps)?"; then
        pacman -Rns --noconfirm "${filtered[@]}"
    fi
else
    echo "none"
fi

step "AUR helper caches"
for d in "$REAL_HOME/.cache/yay" "$REAL_HOME/.cache/paru"; do
    [[ -d "$d" ]] && find "$d" -mindepth 1 -maxdepth 1 -exec rm -rf {} +
done

step "Journal (cap at $JOURNAL_MAX)"
journalctl --vacuum-size="$JOURNAL_MAX"

step "Core dumps"
rm -rf /var/lib/systemd/coredump/* 2>/dev/null

step "Flatpak unused runtimes"
command -v flatpak >/dev/null && flatpak uninstall --unused -y || echo "flatpak not installed"

step "User caches (thumbnails, pip, npm, trash)"
rm -rf "$REAL_HOME/.cache/thumbnails" "$REAL_HOME/.cache/pip" "$REAL_HOME/.npm/_cacache" 2>/dev/null
rm -rf "$REAL_HOME/.local/share/Trash/files/"* "$REAL_HOME/.local/share/Trash/info/"* 2>/dev/null

after=$(used)
step "Done"
freed=$((before - after))
((freed < 0)) && freed=0
echo "Freed: $(human "$freed")  |  Used on /: $(human "$after")"
df -h /
