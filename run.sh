#!/usr/bin/env bash

set -uo pipefail

GIT_NAME="nullbyte6"
GIT_EMAIL="sargent.pointed453@passinbox.com"
GIT_BRANCH="main"

DOTFILES_REPO="git@github.com:nullbyte6/dotfiles.git"
DOTFILES_HTTPS="https://github.com/nullbyte6/dotfiles.git"
DOTFILES_DIR="$HOME/dotfiles"
SSH_KEY="$HOME/.ssh/id_ed25519"

ZSH_PLUGINS=(
    "zsh-autosuggestions|https://github.com/zsh-users/zsh-autosuggestions.git"
    "zsh-syntax-highlighting|https://github.com/zsh-users/zsh-syntax-highlighting.git"
)

OXIDE_REPO="git@github.com:nullbyte6/oxide.git"
OXIDE_HTTPS="https://github.com/nullbyte6/oxide.git"
OXIDE_DIR="$HOME/oxide"

POKEMON_REPO="https://gitlab.com/phoneybadger/pokemon-colorscripts.git"
POKEMON_DIR="$HOME/pokemon-colorscripts"

JDK_DIR="/opt/jdk-25"
JDK_URL="https://download.oracle.com/java/25/latest"

HERMES_REPO="https://github.com/NousResearch/hermes-agent.git"
HERMES_DIR="$HOME/hermes-agent"
HERMES_INSTALL_URL="https://hermes-agent.nousresearch.com/install.sh"

AI_MODEL="qwen3.6:35b-a3b"
AI_CTX=65536
AI_MODEL_CTX="qwen3.6:35b-a3b-64k"
OLLAMA_API="http://localhost:11434"
LMS_MODEL="qwen/qwen3.6-35b-a3b"
LMS_API="http://localhost:1234"
AI_PROVIDER_MODEL=""; AI_BASE_URL=""

ASSUME_YES=
DRY_RUN=0
DO_STEAM=1
DO_AI=1

if [[ -t 1 && -z "${NO_COLOR:-}" ]]; then
    ACCENT=$'\e[38;2;46;204;113m'; MUTED=$'\e[38;2;39;130;82m'
    GREEN=$'\e[38;2;123;198;74m'; RED=$'\e[38;2;222;97;32m'; YELLOW=$'\e[38;2;246;226;57m'
    DIM=$'\e[2m'; BOLD=$'\e[1m'; RESET=$'\e[0m'
else
    ACCENT=; MUTED=; GREEN=; RED=; YELLOW=; DIM=; BOLD=; RESET=
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
    [btop]=bashtop [fastfetch]=fastfetch [bashrc]=bashrc [zshrc]=zshrc
    [ohmyzsh]=ohmyzsh [oxide]=oxide
)
declare -A STOW_OPTS=([ohmyzsh]='--ignore=themes')
ALWAYS_STOW=(bashrc zshrc ohmyzsh oxide)

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

  run.sh               full run: bootstrap, git, ssh, dotfiles, packages, zsh, font, steam, pokemon-colorscripts
  run.sh --yes         same, but answer "yes" to package manager prompts
  run.sh --dry-run     print every change instead of doing it
  run.sh --no-steam    skip the steam section
  run.sh --no-ai       skip Hermes Agent + local model (~22 GB download)
  run.sh --help

Remote:  bash <(curl -fsSL https://raw.githubusercontent.com/nullbyte6/autopilot/main/run.sh) --yes
USAGE_EOF
}

section() {
    SECTION_N=$((SECTION_N + 1))
    printf '\n%s╭─%s %s%02d%s %s%s%s\n' "$ACCENT" "$RESET" "$MUTED" "$SECTION_N" "$RESET" "$BOLD" "$1" "$RESET"
}
info() { printf '%s│%s  %s•%s %s\n' "$ACCENT" "$RESET" "$MUTED" "$RESET" "$*"; }
ok()   { N_OK=$((N_OK + 1));     printf '%s│%s  %s✔%s %s\n' "$ACCENT" "$RESET" "$GREEN" "$RESET" "$*"; }
warn() { N_WARN=$((N_WARN + 1)); printf '%s│%s  %s▲%s %s\n' "$ACCENT" "$RESET" "$YELLOW" "$RESET" "$*"; }
fail() { N_FAIL=$((N_FAIL + 1)); printf '%s│%s  %s✘%s %s\n' "$ACCENT" "$RESET" "$RED" "$RESET" "$*"; }

run() {
    printf '%s│%s  %s$ %s%s\n' "$ACCENT" "$RESET" "$DIM" "$*" "$RESET"
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
        ubuntu)  FAMILY=ubuntu; return ;;
        arch)    FAMILY=arch;   return ;;
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
            build-essential make wget whois cargo bat
            neovim fish zsh kitty fastfetch starship bashtop
            ffmpeg python3-pip python3-venv
            fonts-jetbrains-mono
            claude-desktop
        )
        [[ "$FAMILY" == ubuntu ]] && PACKAGES+=(gnome-tweaks gnome-shell-extension-manager)
        SNAPS=(firefox bitwarden protonmail-bridge spotify yazi:classic code:classic zig:classic)
        FLATPAKS=(org.mozilla.firefox com.bitwarden.desktop com.spotify.Client ch.protonmail.protonmail-bridge com.visualstudio.code)
        [[ "$FAMILY" == debian ]] && PACKAGES+=(flatpak)
        ;;
    arch)
        BOOTSTRAP=(git github-cli stow curl openssh base-devel xclip wl-clipboard pciutils)
        PACKAGES=(
            make wget whois rust bat
            neovim fish zsh kitty fastfetch starship bashtop yazi zig
            ffmpeg python-pip
            ttf-jetbrains-mono
            firefox bitwarden protonmail-bridge spotify claude-desktop visual-studio-code-bin
        )
        SNAPS=(); FLATPAKS=()
        ;;
    fedora)
        BOOTSTRAP=(git gh stow curl openssh-clients xclip wl-clipboard flatpak dnf-plugins-core)
        PACKAGES=(
            make gcc gcc-c++ wget2-wget whois cargo bat claude-desktop
            neovim fish zsh kitty fastfetch starship btop yazi zig
            ffmpeg-free python3-pip
            jetbrains-mono-fonts-all firefox gnome-tweaks
        )
        SNAPS=()
        FLATPAKS=(com.bitwarden.desktop com.spotify.Client ch.protonmail.protonmail-bridge com.visualstudio.code)
        ;;
    suse)
        BOOTSTRAP=(git gh stow curl openssh-clients xclip wl-clipboard flatpak)
        PACKAGES=(
            make gcc gcc-c++ wget whois cargo bat
            neovim fish zsh kitty fastfetch starship bashtop yazi zig
            ffmpeg python3-pip
            jetbrains-mono-fonts MozillaFirefox gnome-tweaks
        )
        SNAPS=()
        FLATPAKS=(com.bitwarden.desktop com.spotify.Client ch.protonmail.protonmail-bridge com.visualstudio.code)
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

install_jdk() {
    local arch tmp
    case "$(uname -m)" in
        x86_64|amd64)  arch=x64 ;;
        aarch64|arm64) arch=aarch64 ;;
        *) fail "No JDK 25 build for $(uname -m)"; return 1 ;;
    esac
    if [[ -x "$JDK_DIR/bin/java" ]]; then
        ok "JDK 25 already in $JDK_DIR"; return 0
    fi
    tmp="$(mktemp -d)"
    if run curl -fL --retry 3 -o "$tmp/jdk-25.tar.gz" "$JDK_URL/jdk-25_linux-${arch}_bin.tar.gz" \
       && run sudo mkdir -p "$JDK_DIR" \
       && run sudo tar -xzf "$tmp/jdk-25.tar.gz" -C "$JDK_DIR" --strip-components=1; then
        ok "JDK 25 extracted to $JDK_DIR"
    else
        fail "Could not install JDK 25 into $JDK_DIR"
    fi
    rm -rf "$tmp"
}

install_hermes() {
    if have hermes; then
        ok "Hermes Agent already installed"; return 0
    fi
    # Distro/AUR package first (only used if a repo actually carries it)
    local pkg
    for pkg in hermes-agent hermes-agent-git; do
        if (( ! DRY_RUN )) && pkg_exists "$pkg"; then
            if install_pkgs "$pkg"; then ok "Hermes Agent installed from repo ($pkg)"; return 0; fi
        fi
    done
    info "No repo package, using the official installer"
    if run bash -c "curl -fsSL '$HERMES_INSTALL_URL' | bash"; then
        ok "Hermes Agent installed"; return 0
    fi
    warn "Official installer failed, cloning $HERMES_REPO and installing from source"
    if [[ -d "$HERMES_DIR/.git" ]]; then run git -C "$HERMES_DIR" pull --ff-only
    else run git clone --depth 1 "$HERMES_REPO" "$HERMES_DIR"; fi || { fail "Could not clone Hermes Agent"; return 1; }
    if run python3 -m venv "$HERMES_DIR/.venv" \
       && run "$HERMES_DIR/.venv/bin/pip" install -e "$HERMES_DIR" \
       && run mkdir -p "$HOME/.local/bin" \
       && run ln -sf "$HERMES_DIR/.venv/bin/hermes" "$HOME/.local/bin/hermes"; then
        ok "Hermes Agent installed from source into $HERMES_DIR"
    else
        fail "Hermes Agent source install failed"; return 1
    fi
}

wait_for_url() {
    local url="$1" i
    (( DRY_RUN )) && return 0
    for i in {1..30}; do curl -fsS "$url" >/dev/null 2>&1 && return 0; sleep 1; done
    return 1
}

setup_ollama() {
    if ! have ollama; then
        if (( ! DRY_RUN )) && pkg_exists ollama && install_pkgs ollama; then :
        else
            info "Using the official Ollama installer"
            run bash -c "curl -fsSL https://ollama.com/install.sh | sh" || { fail "Could not install Ollama"; return 1; }
        fi
    fi
    ok "Ollama available"
    if have systemctl && ! curl -fsS "$OLLAMA_API/api/tags" >/dev/null 2>&1; then
        run sudo systemctl enable --now ollama || true
    fi
    if ! wait_for_url "$OLLAMA_API/api/tags"; then
        info "Starting ollama serve in the background"
        (( DRY_RUN )) || { nohup ollama serve >/dev/null 2>&1 & }
        wait_for_url "$OLLAMA_API/api/tags" || { fail "Ollama server is not responding"; return 1; }
    fi

    run ollama pull "$AI_MODEL" || { fail "Could not pull $AI_MODEL"; return 1; }
    ok "$AI_MODEL pulled"

    # Ollama defaults to a tiny context; Hermes wants 64k+
    local tmp; tmp="$(mktemp -d)"
    printf 'FROM %s\nPARAMETER num_ctx %s\n' "$AI_MODEL" "$AI_CTX" > "$tmp/Modelfile"
    if run ollama create "$AI_MODEL_CTX" -f "$tmp/Modelfile"; then
        ok "Created $AI_MODEL_CTX (num_ctx $AI_CTX)"
        AI_PROVIDER_MODEL="$AI_MODEL_CTX"
    else
        warn "Could not build the long-context variant, using $AI_MODEL as is"
        AI_PROVIDER_MODEL="$AI_MODEL"
    fi
    rm -rf "$tmp"
    AI_BASE_URL="$OLLAMA_API/v1"
}

setup_lmstudio() {
    if ! have lms; then
        if [[ "$FAMILY" == arch ]] && have yay; then
            run yay -S --needed ${ASSUME_YES:+--noconfirm} lmstudio || true
        fi
        [[ -x "$HOME/.lmstudio/bin/lms" ]] && export PATH="$HOME/.lmstudio/bin:$PATH"
    fi
    if ! have lms; then
        warn "LM Studio CLI (lms) not found; install LM Studio from https://lmstudio.ai and re-run"
        return 1
    fi
    run lms get "$LMS_MODEL" -y || { fail "lms could not download $LMS_MODEL"; return 1; }
    run lms server start || true
    wait_for_url "$LMS_API/v1/models" || { fail "LM Studio server is not responding"; return 1; }
    ok "LM Studio serving $LMS_MODEL"
    AI_PROVIDER_MODEL="$LMS_MODEL"
    AI_BASE_URL="$LMS_API/v1"
}

configure_hermes() {
    local cfg="$HOME/.hermes/config.yaml"
    run mkdir -p "$HOME/.hermes"
    if (( DRY_RUN )); then
        info "Would set model.default=$AI_PROVIDER_MODEL, provider=custom, base_url=$AI_BASE_URL in $cfg"
        return 0
    fi
    if python3 - "$cfg" "$AI_PROVIDER_MODEL" "$AI_BASE_URL" <<'PY'
import sys, os
path, model, url = sys.argv[1:4]
try:
    import yaml
except ImportError:
    sys.exit(2)
data = {}
if os.path.exists(path):
    with open(path) as f:
        data = yaml.safe_load(f) or {}
m = data.get("model")
if not isinstance(m, dict):
    m = {}
m.update({"default": model, "provider": "custom", "base_url": url})
data["model"] = m
with open(path, "w") as f:
    yaml.safe_dump(data, f, sort_keys=False)
PY
    then
        ok "Hermes configured to use $AI_PROVIDER_MODEL at $AI_BASE_URL"
    elif [[ ! -e "$cfg" ]]; then
        printf 'model:\n  default: "%s"\n  provider: "custom"\n  base_url: "%s"\n' "$AI_PROVIDER_MODEL" "$AI_BASE_URL" > "$cfg" \
            && ok "Wrote $cfg"
    else
        warn "PyYAML missing and $cfg exists; in Hermes run: /model $AI_PROVIDER_MODEL (base_url $AI_BASE_URL)"
    fi
}

setup_ai() {
    AI_PROVIDER_MODEL=""; AI_BASE_URL=""
    install_hermes || return 1
    if ! setup_ollama; then
        warn "Ollama path failed, falling back to LM Studio"
        setup_lmstudio || { fail "No local model backend could be set up"; return 1; }
    fi
    configure_hermes
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
    if (( DRY_RUN )); then
        info "Would write $list"
    elif printf '%s\n' "$line" | sudo tee "$list" >/dev/null; then
        ok "Claude Desktop repo added"
    else
        fail "Could not write $list"
    fi
}

enable_claude_copr() {
    if dnf copr list 2>/dev/null | grep -q 'wrobelda/claude-desktop'; then
        info "Claude Desktop COPR already enabled"; return 0
    fi
    info "Enabling the unofficial Claude Desktop COPR (wrobelda/claude-desktop)"
    if run sudo dnf copr enable -y wrobelda/claude-desktop; then ok "Claude Desktop COPR enabled"
    else fail "Could not enable the Claude Desktop COPR"; fi
}

ensure_github_key() {
    local pub_body keys="" keys_ok=0
    if ! gh auth status >/dev/null 2>&1; then
        info "Logging in to GitHub (follow the browser prompt)"
        gh auth login -h github.com -p ssh -s admin:public_key -w --skip-ssh-key || warn "gh login failed"
    fi
    gh auth status >/dev/null 2>&1 || { warn "Not logged in to gh. Paste the key here: https://github.com/settings/ssh/new"; return; }

    pub_body="$(awk '{print $2}' "$SSH_KEY.pub")"
    if keys="$(gh api user/keys --jq '.[].key' 2>/dev/null)"; then
        keys_ok=1
    else
        info "Token lacks key permissions, refreshing"
        if gh auth refresh -h github.com -s admin:public_key && keys="$(gh api user/keys --jq '.[].key' 2>/dev/null)"; then
            keys_ok=1
        fi
    fi

    if (( keys_ok )) && grep -qF "$pub_body" <<<"$keys"; then
        ok "Key already registered on GitHub"
    elif (( keys_ok )) && gh ssh-key add "$SSH_KEY.pub" -t "HOME-$(date +%F)"; then
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
        if (( ${#stow_pkgs[@]} )); then
            mapfile -t stow_pkgs < <(printf '%s\n' "${stow_pkgs[@]}" | sort -u)
        fi
    fi

    if (( ${#stow_pkgs[@]} == 0 )); then
        info "Nothing to stow"
        return
    fi

    backup="$HOME/.dotfiles-backup/$(date +%Y%m%d-%H%M%S)"
    for pkg in "${stow_pkgs[@]}"; do
        conflicts="$(cd "$DOTFILES_DIR" && stow -n ${STOW_OPTS[$pkg]:-} -t "$HOME" "$pkg" 2>&1 \
            | sed -n \
                -e 's/.*existing target is neither a link nor a directory: //p' \
                -e 's/.*existing target is not owned by stow: //p' \
                -e 's/.*over existing target \(.*\) since neither a link nor a directory.*/\1/p' \
                -e 's/.*over existing target \(.*\) since .*not owned by stow.*/\1/p' \
            | sort -u)"
        while IFS= read -r f; do
            [[ -z "$f" ]] && continue
            warn "Backing up existing ~/$f"
            run mkdir -p "$backup/$(dirname "$f")"
            run mv "$HOME/$f" "$backup/$f"
        done <<<"$conflicts"
        if (cd "$DOTFILES_DIR" && run stow -R ${STOW_OPTS[$pkg]:-} -t "$HOME" "$pkg"); then ok "stowed $pkg"
        else fail "stow failed for $pkg"; fi
    done
}

setup_zsh() {
    local zsh_path user current
    zsh_path="$(command -v zsh || true)"
    if [[ -z "$zsh_path" ]]; then
        (( DRY_RUN )) && zsh_path=/usr/bin/zsh || { fail "zsh is not installed, cannot set it as default shell"; return 1; }
    fi

    if [[ -d "$DOTFILES_DIR/.git" ]]; then
        if (cd "$DOTFILES_DIR" && run git submodule update --init --recursive); then
            ok "Oh My Zsh and powerlevel10k submodules up to date"
        else
            fail "Could not update the Oh My Zsh submodules"
        fi
    else
        warn "No dotfiles checkout, Oh My Zsh and powerlevel10k are missing"
    fi

    if [[ -e "$HOME/.oh-my-zsh/oh-my-zsh.sh" ]]; then ok "Oh My Zsh is available in ~/.oh-my-zsh"
    elif (( ! DRY_RUN )); then warn "~/.oh-my-zsh is not in place, check the ohmyzsh stow"; fi

    local entry plugin_dir
    for entry in "${ZSH_PLUGINS[@]}"; do
        plugin_dir="$HOME/.oh-my-zsh/custom/plugins/${entry%%|*}"
        if [[ -d "$plugin_dir/.git" ]]; then
            run git -C "$plugin_dir" pull --ff-only && ok "${entry%%|*} updated" || warn "Could not pull ${entry%%|*}"
        else
            run git clone --depth 1 "${entry#*|}" "$plugin_dir" && ok "${entry%%|*} cloned" || fail "Could not clone ${entry%%|*}"
        fi
    done

    if ! grep -qxF "$zsh_path" /etc/shells 2>/dev/null; then
        info "Registering $zsh_path in /etc/shells"
        if (( DRY_RUN )); then run sh -c "echo $zsh_path >> /etc/shells"
        else printf '%s\n' "$zsh_path" | sudo tee -a /etc/shells >/dev/null || { fail "Could not update /etc/shells"; return 1; }
        fi
    fi

    user="${USER:-$(id -un)}"
    current="$(getent passwd "$user" | cut -d: -f7)"
    if [[ "$current" == "$zsh_path" ]]; then
        ok "zsh is already the default shell"
    elif run sudo chsh -s "$zsh_path" "$user"; then
        ok "Default shell set to zsh (log out and back in to apply)"
    else
        fail "Could not set zsh as the default shell"
    fi
}

steam_arch() {
    local gpu_pkgs=(lib32-mesa vulkan-icd-loader lib32-vulkan-icd-loader)
    local gpu; gpu="$(lspci 2>/dev/null | grep -Ei 'vga|3d' || true)"
    gpu="${gpu,,}"
    [[ "$gpu" == *nvidia* ]] && gpu_pkgs+=(nvidia-utils lib32-nvidia-utils)
    [[ "$gpu" == *amd* || "$gpu" == *radeon* || "$gpu" == *"ati technologies"* ]] && gpu_pkgs+=(vulkan-radeon lib32-vulkan-radeon)
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
            --no-ai)      DO_AI=0 ;;
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

    if (( EUID == 0 )); then
        sudo() { "$@"; }
    elif ! have sudo; then
        fail "sudo is required (or run as root)"; exit 1
    fi

    section "Privileges"
    if (( DRY_RUN )); then
        info "Skipping sudo prompt (dry run)"
    elif (( EUID == 0 )); then
        ok "running as root"
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

    [[ "$FAMILY" == fedora ]] && enable_claude_copr
    [[ "$FAMILY" == suse ]] && warn "No Claude Desktop package exists for openSUSE, skipping it"

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
    elif run git clone --recurse-submodules "$DOTFILES_REPO" "$DOTFILES_DIR"; then
        ok "dotfiles cloned to $DOTFILES_DIR"
    else
        warn "SSH clone failed, retrying over HTTPS"
        if GIT_TERMINAL_PROMPT=0 run git clone --recurse-submodules "$DOTFILES_HTTPS" "$DOTFILES_DIR"; then
            run git -C "$DOTFILES_DIR" remote set-url origin "$DOTFILES_REPO"
            ok "dotfiles cloned to $DOTFILES_DIR"
        else
            fail "Could not clone dotfiles"
        fi
    fi

    stow_dotfiles

    section "Packages"
    install_group "Packages" "${PACKAGES[@]}"

    if [[ "$FAMILY" == ubuntu || "$FAMILY" == debian ]] && have batcat && ! have bat; then
        run mkdir -p "$HOME/.local/bin"
        run ln -sf "$(command -v batcat)" "$HOME/.local/bin/bat" && ok "bat linked to batcat in ~/.local/bin"
    fi

    section "Oxide"
    if [[ -d "$OXIDE_DIR/.git" ]]; then
        run git -C "$OXIDE_DIR" pull --ff-only && ok "oxide updated" || warn "Could not pull oxide (local changes?)"
    elif run git clone "$OXIDE_REPO" "$OXIDE_DIR"; then
        ok "oxide cloned to $OXIDE_DIR"
    else
        warn "SSH clone failed, retrying over HTTPS"
        if GIT_TERMINAL_PROMPT=0 run git clone "$OXIDE_HTTPS" "$OXIDE_DIR"; then
            run git -C "$OXIDE_DIR" remote set-url origin "$OXIDE_REPO"
            ok "oxide cloned to $OXIDE_DIR"
        else
            fail "Could not clone oxide"
        fi
    fi

    if [[ -f "$OXIDE_DIR/install.sh" ]]; then
        if have cargo || (( DRY_RUN )); then
            if (cd "$OXIDE_DIR" && run bash ./install.sh); then ok "oxide built and installed"
            else fail "oxide install failed"; fi
        else
            fail "cargo is not installed, cannot build oxide"
        fi
    elif (( ! DRY_RUN )); then
        warn "No install.sh in $OXIDE_DIR, skipping install"
    fi

    section "Zsh"
    setup_zsh

    section "JDK"
    install_jdk

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
            run sudo flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo
            for app in "${FLATPAKS[@]}"; do
                if flatpak info "$app" >/dev/null 2>&1; then info "$app already installed"
                else run sudo flatpak install -y flathub "$app" && ok "flatpak $app installed" || fail "flatpak $app failed"; fi
            done
            run sudo flatpak update -y && ok "Flatpaks updated" || warn "flatpak update reported problems"
        else
            warn "flatpak isn't available, skipping GUI apps"
        fi
    fi

    section "Font"
    if have fc-cache; then
        run fc-cache -f
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

    if (( DO_AI )); then
        section "Hermes Agent + local model"
        setup_ai
    else
        info "Hermes Agent skipped (--no-ai)"
    fi

    section "Pokémon colorscripts"
    if [[ -d "$POKEMON_DIR/.git" ]]; then
        run git -C "$POKEMON_DIR" pull --ff-only && ok "pokemon-colorscripts updated" || warn "Could not pull pokemon-colorscripts (local changes?)"
    else
        run git clone "$POKEMON_REPO" "$POKEMON_DIR" && ok "pokemon-colorscripts cloned to $POKEMON_DIR" || fail "Could not clone pokemon-colorscripts"
    fi

    if [[ -f "$POKEMON_DIR/install.sh" ]]; then
        if (cd "$POKEMON_DIR" && run sudo sh ./install.sh); then ok "pokemon-colorscripts installed"
        else fail "pokemon-colorscripts install failed"; fi
    elif (( ! DRY_RUN )); then
        warn "No install.sh in $POKEMON_DIR, skipping install"
    fi

    printf '\n%s╰─%s %sDone%s  %s✔ %d%s  %s▲ %d%s  %s✘ %d%s\n' \
        "$ACCENT" "$RESET" "$BOLD" "$RESET" "$GREEN" "$N_OK" "$RESET" "$YELLOW" "$N_WARN" "$RESET" "$RED" "$N_FAIL" "$RESET"
    if (( ${#SKIPPED_PKGS[@]} )); then
        printf '   %sNot installed (no repo carries them): %s%s\n' "$DIM" "${SKIPPED_PKGS[*]}" "$RESET"
    fi
    printf '   %sRe-run any time to update everything.%s\n\n' "$DIM" "$RESET"

    (( N_FAIL == 0 ))
}

main "$@"; exit $?
