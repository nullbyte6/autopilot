#!/usr/bin/env bash

set -uo pipefail

GIT_NAME="nullbyte6"
GIT_EMAIL="sargent.pointed453@passinbox.com"
GIT_BRANCH="main"

DOTFILES_REPO="git@github.com:nullbyte6/dotfiles.git"
DOTFILES_HTTPS="https://github.com/nullbyte6/dotfiles.git"
DOTFILES_DIR="$HOME/dotfiles"
SSH_KEY="$HOME/.ssh/id_ed25519"

POKEMON_REPO="https://gitlab.com/phoneybadger/pokemon-colorscripts.git"
POKEMON_DIR="$HOME/pokemon-colorscripts"

ASSUME_YES=
DRY_RUN=0
DO_STEAM=1

if [[ -t 1 && -z "${NO_COLOR:-}" ]]; then
    GOLD=$'\e[38;2;230;213;115m'; BROWN=$'\e[38;2;156;131;82m'
    GREEN=$'\e[38;2;123;198;74m'; RED=$'\e[38;2;222;97;32m'; YELLOW=$'\e[38;2;246;226;57m'
    DIM=$'\e[2m'; BOLD=$'\e[1m'; RESET=$'\e[0m'
else
    GOLD=; BROWN=; GREEN=; RED=; YELLOW=; DIM=; BOLD=; RESET=
fi

N_OK=0; N_WARN=0; N_FAIL=0
SKIPPED_PKGS=()
SECTION_N=0
FAMILY=""
AVAIL=(); MISSING=()
BOOTSTRAP=(); PACKAGES=(); SNAPS=(); FLATPAKS=()
SUDO_KEEPALIVE=

declare -A STOW_FOR=(
    [neovim]=neovim [fish]=fish [kitty]=kitty [alacritty]=alacritty
    [ghostty]=ghostty [starship]=starship [yazi]=yazi [bashtop]=bashtop
    [bashrc]=bashrc [zshrc]=zshrc
)
ALWAYS_STOW=(bashrc zshrc)

logo() {
    cat <<'LOGO_EOF'
 ▗▄▖ ▗▖ ▗▖▗▄▄▄▖▗▄▖ ▗▄▄▖▗▄▄▄▖▗▖    ▗▄▖▗▄▄▄▖
▐▌ ▐▌▐▌ ▐▌  █ ▐▌ ▐▌▐▌ ▐▌ █  ▐▌   ▐▌ ▐▌ █  
▐▛▀▜▌▐▌ ▐▌  █ ▐▌ ▐▌▐▛▀▘  █  ▐▌   ▐▌ ▐▌ █  v0.1.0
▐▌ ▐▌▝▚▄▞▘  █ ▝▚▄▞▘▐▌  ▗▄█▄▖▐▙▄▄▖▝▚▄▞▘ █  by nullbyte6
LOGO_EOF
}

usage() {
    cat <<'USAGE_EOF'
autopilot: rebuild (or refresh) my whole setup on any machine. Safe to re-run.

  run.sh               full run: bootstrap, git, ssh, dotfiles, packages, font, steam, pokemon-colorscripts
  run.sh --yes         same, but answer "yes" to package manager prompts
  run.sh --dry-run     print every change instead of doing it
  run.sh --no-steam    skip the steam section
  run.sh --help

Remote:  bash <(curl -fsSL https://raw.githubusercontent.com/nullbyte6/autopilot/main/run.sh) --yes
USAGE_EOF
}

section() {
    SECTION_N=$((SECTION_N + 1))
    printf '\n%s╭─%s %s%02d%s %s%s%s\n' "$GOLD" "$RESET" "$BROWN" "$SECTION_N" "$RESET" "$BOLD" "$1" "$RESET"
}
info() { printf '%s│%s  %s•%s %s\n' "$GOLD" "$RESET" "$BROWN" "$RESET" "$*"; }
ok()   { N_OK=$((N_OK + 1));     printf '%s│%s  %s✔%s %s\n' "$GOLD" "$RESET" "$GREEN" "$RESET" "$*"; }
warn() { N_WARN=$((N_WARN + 1)); printf '%s│%s  %s▲%s %s\n' "$GOLD" "$RESET" "$YELLOW" "$RESET" "$*"; }
fail() { N_FAIL=$((N_FAIL + 1)); printf '%s│%s  %s✘%s %s\n' "$GOLD" "$RESET" "$RED" "$RESET" "$*"; }

run() {
    printf '%s│%s  %s$ %s%s\n' "$GOLD" "$RESET" "$DIM" "$*" "$RESET"
    (( DRY_RUN )) && return 0
    "$@"
}

have() { command -v "$1" >/dev/null 2>&1; }

check_distro() {
    local ID="" ID_LIKE="" NAME="your system"
    if [[ -r /etc/os-release ]]; then
        source /etc/os-release
    fi
    echo "Your distribution is $NAME"

    case "${ID:-}" in
        ubuntu) FAMILY=ubuntu; return ;;
        arch)   FAMILY=arch;   return ;;
    esac
    case " ${ID:-} ${ID_LIKE:-} " in
        *" arch "*)                    FAMILY=arch   ;;
        *" ubuntu "*)                  FAMILY=ubuntu ;;
        *" debian "*)                  FAMILY=debian ;;
        *" fedora "*|*" rhel "*)       FAMILY=fedora ;;
        *" suse "*|*" opensuse "*)     FAMILY=suse   ;;
    esac
}

set_package_lists() {
    case "$FAMILY" in
    ubuntu|debian)
        BOOTSTRAP=(git gh stow curl openssh-client xclip wl-clipboard)
        PACKAGES=(
            build-essential make wget whois
            neovim fish kitty alacritty ghostty starship bashtop
            ffmpeg python3-pip python3-venv default-jdk
            fonts-jetbrains-mono
            claude-desktop
        )
        [[ "$FAMILY" == ubuntu ]] && PACKAGES+=(gnome-tweaks gnome-shell-extension-manager)
        SNAPS=(firefox bitwarden protonmail-bridge spotify yazi:classic intellij-idea:classic code:classic zig:classic)
        FLATPAKS=(org.mozilla.firefox com.bitwarden.desktop com.spotify.Client ch.protonmail.protonmail-bridge
                  com.jetbrains.IntelliJ-IDEA-Ultimate com.visualstudio.code)
        [[ "$FAMILY" == debian ]] && PACKAGES+=(flatpak)
        ;;
    arch)
        BOOTSTRAP=(git github-cli stow curl openssh base-devel xclip wl-clipboard pciutils)
        PACKAGES=(
            make wget whois
            neovim fish kitty alacritty ghostty starship bashtop yazi zig
            ffmpeg python-pip jdk-openjdk
            ttf-jetbrains-mono
            firefox bitwarden protonmail-bridge spotify
            intellij-idea-ultimate-edition visual-studio-code-bin
        )
        SNAPS=(); FLATPAKS=()
        ;;
    fedora)
        BOOTSTRAP=(git gh stow curl openssh-clients xclip wl-clipboard flatpak)
        PACKAGES=(
            make gcc gcc-c++ wget whois
            neovim fish kitty alacritty ghostty starship btop yazi zig
            ffmpeg-free python3-pip java-latest-openjdk-devel
            jetbrains-mono-fonts-all firefox gnome-tweaks
        )
        SNAPS=()
        FLATPAKS=(com.bitwarden.desktop com.spotify.Client ch.protonmail.protonmail-bridge
                  com.jetbrains.IntelliJ-IDEA-Ultimate com.visualstudio.code)
        ;;
    suse)
        BOOTSTRAP=(git gh stow curl openssh-clients xclip wl-clipboard flatpak)
        PACKAGES=(
            make gcc gcc-c++ wget whois
            neovim fish kitty alacritty starship bashtop yazi zig
            ffmpeg python3-pip java-devel
            jetbrains-mono-fonts MozillaFirefox gnome-tweaks
        )
        SNAPS=()
        FLATPAKS=(com.bitwarden.desktop com.spotify.Client ch.protonmail.protonmail-bridge
                  com.jetbrains.IntelliJ-IDEA-Ultimate com.visualstudio.code)
        ;;
    esac
}

sync_index() {
    case "$FAMILY" in
        ubuntu|debian) run sudo apt update ;;
        arch)          run sudo pacman -Syu ${ASSUME_YES:+--noconfirm} ;;
        fedora)        run sudo dnf makecache ;;
        suse)          run sudo zypper refresh ;;
    esac
}

pkg_exists() {
    case "$FAMILY" in
        ubuntu|debian) apt-cache show "$1" >/dev/null 2>&1 ;;
        arch)          if have yay; then yay -Si "$1" >/dev/null 2>&1 || pacman -Si "$1" >/dev/null 2>&1
                       else pacman -Si "$1" >/dev/null 2>&1; fi ;;
        fedora)        dnf -q info "$1" >/dev/null 2>&1 ;;
        suse)          zypper -q info "$1" 2>/dev/null | grep -q '^Name' ;;
    esac
}

filter_available() {
    AVAIL=(); MISSING=()
    local p
    for p in "$@"; do
        if (( DRY_RUN )) && [[ "$FAMILY" == arch ]] && ! have yay; then AVAIL+=("$p"); continue; fi
        if pkg_exists "$p"; then AVAIL+=("$p"); else MISSING+=("$p"); fi
    done
    if (( ${#MISSING[@]} )); then
        warn "Not in any enabled repo, skipped: ${MISSING[*]}"
        SKIPPED_PKGS+=("${MISSING[@]}")
    fi
}

install_pkgs() {
    (( $# )) || return 0
    case "$FAMILY" in
        ubuntu|debian) run sudo apt install ${ASSUME_YES:+-y} "$@" ;;
        fedora)        run sudo dnf install ${ASSUME_YES:+-y} "$@" ;;
        suse)          run sudo zypper install ${ASSUME_YES:+-y} "$@" ;;
        arch)
            local via_yay=() via_pacman=() p
            for p in "$@"; do
                if have yay && yay -Si "$p" >/dev/null 2>&1; then via_yay+=("$p")
                else via_pacman+=("$p"); fi
            done
            local rc=0
            if (( ${#via_yay[@]} ));    then run yay -S --needed ${ASSUME_YES:+--noconfirm} "${via_yay[@]}" || rc=1; fi
            if (( ${#via_pacman[@]} )); then run sudo pacman -S --needed ${ASSUME_YES:+--noconfirm} "${via_pacman[@]}" || rc=1; fi
            return $rc ;;
    esac
}

install_group() {
    local label="$1"; shift
    filter_available "$@"
    if (( ${#AVAIL[@]} == 0 )); then info "$label: nothing to install"; return; fi
    if install_pkgs "${AVAIL[@]}"; then ok "$label installed/updated (${#AVAIL[@]} packages)"
    else fail "$label: package manager reported errors"; fi
}

clip() {
    if   [[ -n "${WAYLAND_DISPLAY:-}" ]] && have wl-copy; then wl-copy
    elif have xclip; then xclip -selection clipboard
    elif have xsel;  then xsel --clipboard --input
    else return 1; fi
}

add_claude_repo() {
    local keyring=/usr/share/keyrings/claude-desktop-archive-keyring.asc
    local list=/etc/apt/sources.list.d/claude-desktop.list
    local url=https://downloads.claude.ai/claude-desktop/key.asc
    local line="deb [signed-by=$keyring] https://downloads.claude.ai/claude-desktop/apt/stable stable main"
    if [[ -f "$list" || -f /etc/apt/sources.list.d/claude-desktop.sources ]]; then
        info "Claude Desktop apt repo already configured"; return 0
    fi
    info "Adding the Claude Desktop apt repo"
    if   have curl; then run sudo curl -fsSLo "$keyring" "$url"
    elif have wget; then run sudo wget -qO "$keyring" "$url"
    else run sudo python3 -c "import urllib.request,sys; open(sys.argv[1],'wb').write(urllib.request.urlopen(sys.argv[2]).read())" "$keyring" "$url"
    fi || { fail "Could not download the Claude Desktop key"; return 1; }
    printf '%s\n' "$line" | run sudo tee "$list" >/dev/null && ok "Claude Desktop repo added"
}

ensure_github_key() {
    local pub_body keys=""
    if ! gh auth status >/dev/null 2>&1; then
        info "Logging in to GitHub (follow the browser prompt)"
        gh auth login -h github.com -p ssh -s admin:public_key -w --skip-ssh-key || warn "gh login failed"
    fi
    gh auth status >/dev/null 2>&1 || { warn "Not logged in to gh. Paste the key here: https://github.com/settings/ssh/new"; return; }

    pub_body="$(awk '{print $2}' "$SSH_KEY.pub")"
    keys="$(gh api user/keys --jq '.[].key' 2>/dev/null)" || {
        info "Token lacks key permissions, refreshing"
        gh auth refresh -h github.com -s admin:public_key && keys="$(gh api user/keys --jq '.[].key' 2>/dev/null)"
    }
    if grep -qF "$pub_body" <<<"${keys:-}"; then
        ok "Key already registered on GitHub"
    elif [[ -n "${keys+x}" ]] && gh ssh-key add "$SSH_KEY.pub" -t "$(hostname)-$(date +%F)"; then
        ok "Key added to GitHub through gh"
    else
        warn "gh couldn't upload it. Paste the clipboard here: https://github.com/settings/ssh/new"
    fi
}

stow_dotfiles() {
    local wanted app pkg f conflicts backup
    local stow_pkgs=()

    if [[ -d "$DOTFILES_DIR" ]]; then
        wanted=" ${PACKAGES[*]} ${SNAPS[*]%%:*} ${FLATPAKS[*]} ${ALWAYS_STOW[*]} "
        for app in "${!STOW_FOR[@]}"; do
            [[ "$wanted" == *" $app "* && -d "$DOTFILES_DIR/${STOW_FOR[$app]}" ]] && stow_pkgs+=("${STOW_FOR[$app]}")
        done
        mapfile -t stow_pkgs < <(printf '%s\n' "${stow_pkgs[@]}" | sort -u)
    fi

    if (( ${#stow_pkgs[@]} == 0 )); then
        info "Nothing to stow"
        return
    fi

    backup="$HOME/.dotfiles-backup/$(date +%Y%m%d-%H%M%S)"
    for pkg in "${stow_pkgs[@]}"; do
        conflicts="$(cd "$DOTFILES_DIR" && stow -n -t "$HOME" "$pkg" 2>&1 \
            | sed -n \
                -e 's/.*existing target \(is neither a link nor a directory\|is not owned by stow\): //p' \
            | sort -u)"
        while IFS= read -r f; do
            [[ -z "$f" ]] && continue
            warn "Backing up existing ~/$f"
            run mkdir -p "$backup/$(dirname "$f")"
            run mv "$HOME/$f" "$backup/$f"
        done <<<"$conflicts"
        if (cd "$DOTFILES_DIR" && run stow -R -t "$HOME" "$pkg"); then ok "stowed $pkg"
        else fail "stow failed for $pkg"; fi
    done
}

steam_arch() {
    local gpu_pkgs=(lib32-mesa vulkan-icd-loader lib32-vulkan-icd-loader)
    local gpu; gpu="$(lspci 2>/dev/null | grep -Ei 'vga|3d' || true)"
    gpu="${gpu,,}"
    [[ "$gpu" == *nvidia* ]] && gpu_pkgs+=(nvidia-utils lib32-nvidia-utils)
    [[ "$gpu" == *amd* || "$gpu" == *radeon* || "$gpu" == *ati* ]] && gpu_pkgs+=(vulkan-radeon lib32-vulkan-radeon)
    [[ "$gpu" == *intel* ]] && gpu_pkgs+=(vulkan-intel lib32-vulkan-intel)
    info "GPU packages: ${gpu_pkgs[*]}"
    install_group "Steam" steam ttf-liberation "${gpu_pkgs[@]}"
}

steam_ubuntu() {
    if have snap; then
        if snap list steam >/dev/null 2>&1; then info "steam snap already installed (refreshed above)"
        else run sudo snap install steam && ok "steam installed" || fail "steam snap failed"; fi
    else
        run sudo add-apt-repository -y multiverse
        run sudo dpkg --add-architecture i386
        run sudo apt update
        install_group "Steam" steam-installer
    fi
}

steam_debian() {
    run sudo dpkg --add-architecture i386
    run sudo apt update
    install_group "Steam" steam-installer
}

steam_fedora() {
    if ! rpm -q rpmfusion-free-release >/dev/null 2>&1; then
        run sudo dnf install -y \
            "https://mirrors.rpmfusion.org/free/fedora/rpmfusion-free-release-$(rpm -E %fedora).noarch.rpm" \
            "https://mirrors.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-$(rpm -E %fedora).noarch.rpm"
    fi
    install_group "Steam" steam
}

steam_suse() { install_group "Steam" steam; }

main() {
    local arg
    for arg in "$@"; do
        case "$arg" in
            -y|--yes)     ASSUME_YES=1 ;;
            -n|--dry-run) DRY_RUN=1 ;;
            --no-steam)   DO_STEAM=0 ;;
            -h|--help)    usage; exit 0 ;;
            *) echo "Unknown option: $arg (try --help)"; exit 1 ;;
        esac
    done

    if [[ ! -t 0 ]] && { exec </dev/tty; } 2>/dev/null; then :; fi

    [[ -t 1 && -n "${TERM:-}" ]] && clear
    logo

    check_distro
    if [[ -z "$FAMILY" ]]; then
        fail "Unsupported distribution. Supported: Ubuntu/Debian, Arch, Fedora, openSUSE."
        exit 1
    fi
    (( DRY_RUN )) && warn "Dry run: nothing will be changed."
    set_package_lists

    section "Privileges"
    if (( DRY_RUN )); then
        info "Skipping sudo prompt (dry run)"
    elif sudo -v; then
        ok "sudo ready"
        ( while true; do sudo -n true; sleep 50; kill -0 "$$" 2>/dev/null || exit; done ) &
        SUDO_KEEPALIVE=$!
        trap 'kill "$SUDO_KEEPALIVE" 2>/dev/null' EXIT
    else
        fail "Need sudo to continue"; exit 1
    fi

    section "Package index"
    if [[ "$FAMILY" == arch ]] && (( DO_STEAM )) && ! grep -q '^\[multilib\]' /etc/pacman.conf 2>/dev/null; then
        info "Enabling [multilib] first so the single -Syu below covers steam too"
        run sudo sed -i '/^#\[multilib\]/,/^#Include/ s/^#//' /etc/pacman.conf
    fi
    [[ "$FAMILY" == ubuntu || "$FAMILY" == debian ]] && add_claude_repo

    sync_index && ok "Index synced and system refreshed (${FAMILY})" || fail "Could not sync package index"

    section "Bootstrap tools"
    install_group "Bootstrap" "${BOOTSTRAP[@]}"

    if [[ "$FAMILY" == arch ]] && ! have yay; then
        info "yay not found, building it from the AUR"
        if (( DRY_RUN )); then
            run git clone https://aur.archlinux.org/yay-bin.git /tmp/yay-bin
        else
            local tmp
            tmp="$(mktemp -d)"
            if git clone --depth 1 https://aur.archlinux.org/yay-bin.git "$tmp/yay-bin" \
               && (cd "$tmp/yay-bin" && makepkg -si ${ASSUME_YES:+--noconfirm}); then
                ok "yay installed"
            else
                fail "yay failed to build: falling back to pacman only"
            fi
            rm -rf "$tmp"
        fi
    fi

    section "Git"
    run git config --global user.name  "$GIT_NAME"
    run git config --global user.email "$GIT_EMAIL"
    run git config --global init.defaultBranch "$GIT_BRANCH"
    run git config --global pull.ff only
    run git config --global core.editor nvim
    ok "git configured as ${GIT_NAME} <${GIT_EMAIL}>"

    section "SSH & GitHub"
    run mkdir -p "$HOME/.ssh"; run chmod 700 "$HOME/.ssh"

    if [[ -f "$SSH_KEY" ]]; then
        ok "SSH key already exists ($SSH_KEY)"
    else
        info "Generating a new ed25519 key (you'll be asked for a passphrase)"
        if run ssh-keygen -t ed25519 -C "$GIT_EMAIL" -f "$SSH_KEY"; then ok "SSH key created"
        else fail "ssh-keygen failed"; fi
    fi

    if (( DRY_RUN )); then
        run sh -c "cat $SSH_KEY.pub | clip"
        run gh ssh-key add "$SSH_KEY.pub"
    elif [[ -f "$SSH_KEY.pub" ]]; then
        if clip < "$SSH_KEY.pub"; then ok "Public key copied to clipboard"
        else warn "No clipboard tool worked; key is at $SSH_KEY.pub"; fi
        have gh && ensure_github_key
    fi

    export GIT_SSH_COMMAND="ssh -o StrictHostKeyChecking=accept-new"

    section "Dotfiles"
    if [[ -d "$DOTFILES_DIR/.git" ]]; then
        run git -C "$DOTFILES_DIR" pull --ff-only && ok "dotfiles updated" || warn "Could not pull dotfiles (local changes?)"
    else
        run git clone "$DOTFILES_REPO" "$DOTFILES_DIR" && ok "dotfiles cloned to $DOTFILES_DIR" || fail "Could not clone dotfiles"
    fi
    stow_dotfiles

    section "Packages"
    install_group "Packages" "${PACKAGES[@]}"

    if (( ${#SNAPS[@]} )) && have snap; then
        section "Snaps"
        local entry name flag
        for entry in "${SNAPS[@]}"; do
            name="${entry%%:*}"; flag=""; [[ "$entry" == *:classic ]] && flag="--classic"
            if snap list "$name" >/dev/null 2>&1; then info "$name already installed"
            else run sudo snap install "$name" $flag && ok "snap $name installed" || fail "snap $name failed"; fi
        done
        run sudo snap refresh && ok "Snaps refreshed" || warn "snap refresh reported problems"
    elif (( ${#FLATPAKS[@]} )); then
        section "Flatpaks"
        if have flatpak; then
            local app
            run flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo
            for app in "${FLATPAKS[@]}"; do
                if flatpak info "$app" >/dev/null 2>&1; then info "$app already installed"
                else run flatpak install -y flathub "$app" && ok "flatpak $app installed" || fail "flatpak $app failed"; fi
            done
            run flatpak update -y && ok "Flatpaks updated" || warn "flatpak update reported problems"
        else
            warn "flatpak isn't available, skipping GUI apps"
        fi
    fi

    section "Font"
    if have fc-cache; then
        run fc-cache -f >/dev/null 2>&1
        if fc-list 2>/dev/null | grep -qi 'JetBrains *Mono'; then ok "JetBrainsMono is available"
        else (( DRY_RUN )) || warn "JetBrainsMono not found by fontconfig"; fi
    else
        warn "fc-cache missing, can't verify the font"
    fi

    if (( DO_STEAM )); then
        section "Steam"
        "steam_${FAMILY}"
    else
        info "Steam skipped (--no-steam)"
    fi

    section "Pokémon colorscripts"
    if [[ -d "$POKEMON_DIR/.git" ]]; then
        run git -C "$POKEMON_DIR" pull --ff-only && ok "pokemon-colorscripts updated" || warn "Could not pull pokemon-colorscripts (local changes?)"
    else
        run git clone "$POKEMON_REPO" "$POKEMON_DIR" && ok "pokemon-colorscripts cloned to $POKEMON_DIR" || fail "Could not clone pokemon-colorscripts"
    fi

    if [[ -x "$POKEMON_DIR/install.sh" ]]; then
        if (cd "$POKEMON_DIR" && run sudo ./install.sh); then ok "pokemon-colorscripts installed"
        else fail "pokemon-colorscripts install failed"; fi
    elif (( ! DRY_RUN )); then
        warn "No install.sh in $POKEMON_DIR, skipping install"
    fi

    printf '\n%s╰─%s %sDone%s  %s✔ %d%s  %s▲ %d%s  %s✘ %d%s\n' \
        "$GOLD" "$RESET" "$BOLD" "$RESET" "$GREEN" "$N_OK" "$RESET" "$YELLOW" "$N_WARN" "$RESET" "$RED" "$N_FAIL" "$RESET"
    if (( ${#SKIPPED_PKGS[@]} )); then
        printf '   %sNot installed (no repo carries them): %s%s\n' "$DIM" "${SKIPPED_PKGS[*]}" "$RESET"
    fi
    printf '   %sRe-run any time to update everything.%s\n\n' "$DIM" "$RESET"

    (( N_FAIL == 0 ))
}

main "$@"; exit $?
