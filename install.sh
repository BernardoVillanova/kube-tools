#!/usr/bin/env bash
# ==============================================================================
# kube-tools: Automated installer & shell configurator for Kubernetes CLI tools
# Tools: fzf, kubectx, kubens, helm, k9s, kubetail, kube-ps1
# Aliases: kctx -> kubectx, kns -> kubens
# ==============================================================================

set -euo pipefail

INSTALL_BIN_DIR="${HOME}/.local/bin"
INSTALL_SHARE_DIR="${HOME}/.local/share/kube-tools"
MARKER_BEGIN="# >>> kube-tools initialize >>>"
MARKER_END="# <<< kube-tools initialize <<<"

DRY_RUN=false
UNINSTALL=false

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info()  { printf "${BLUE}[INFO]${NC} %s\n" "$*"; }
log_ok()    { printf "${GREEN}[OK]${NC} %s\n" "$*"; }
log_warn()  { printf "${YELLOW}[WARN]${NC} %s\n" "$*"; }
log_error() { printf "${RED}[ERROR]${NC} %s\n" "$*" >&2; }

usage() {
    cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Options:
  --dry-run      Detect OS, shell, and package manager without mutating the system
  --uninstall    Remove kube-tools managed binaries, shared repos, and shell aliases (rollback)
  -h, --help     Show this help message
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --dry-run)   DRY_RUN=true; shift ;;
        --uninstall|--rollback) UNINSTALL=true; shift ;;
        -h|--help)   usage; exit 0 ;;
        *) log_error "Unknown option: $1"; usage; exit 1 ;;
    esac
done

run_cmd() {
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Would execute: $*"
    else
        "$@"
    fi
}

# ------------------------------------------------------------------------------
# 1. Environment Detection (OS, Distro, Arch, Shell, Package Manager)
# ------------------------------------------------------------------------------
detect_environment() {
    OS_KERNEL="$(uname -s)"
    ARCH_RAW="$(uname -m)"

    case "$OS_KERNEL" in
        Linux*)  OS="linux" ;;
        Darwin*) OS="darwin" ;;
        *)       log_error "Unsupported OS: $OS_KERNEL"; exit 1 ;;
    esac

    case "$ARCH_RAW" in
        x86_64|amd64)   ARCH="amd64"; ARCH_K9S="amd64" ;;
        aarch64|arm64)  ARCH="arm64"; ARCH_K9S="arm64" ;;
        *)              log_error "Unsupported architecture: $ARCH_RAW"; exit 1 ;;
    esac

    DISTRO="unknown"
    if [[ "$OS" == "linux" && -f /etc/os-release ]]; then
        # shellcheck disable=SC1091
        . /etc/os-release
        DISTRO="${ID:-unknown}"
    elif [[ "$OS" == "darwin" ]]; then
        DISTRO="macos"
    fi

    PKG_MGR="none"
    if command -v brew >/dev/null 2>&1; then
        PKG_MGR="brew"
    elif command -v apt-get >/dev/null 2>&1; then
        PKG_MGR="apt"
    elif command -v pacman >/dev/null 2>&1; then
        PKG_MGR="pacman"
    elif command -v dnf >/dev/null 2>&1; then
        PKG_MGR="dnf"
    elif command -v yum >/dev/null 2>&1; then
        PKG_MGR="yum"
    elif command -v zypper >/dev/null 2>&1; then
        PKG_MGR="zypper"
    elif command -v apk >/dev/null 2>&1; then
        PKG_MGR="apk"
    fi

    USER_SHELL="$(basename "${SHELL:-bash}")"

    log_info "Detected OS:           ${OS} (${DISTRO})"
    log_info "Detected Architecture: ${ARCH} (${ARCH_RAW})"
    log_info "Detected Package Mgr:  ${PKG_MGR}"
    log_info "Detected User Shell:   ${USER_SHELL}"
}

# ------------------------------------------------------------------------------
# 2. Privilege helper for base dependencies (git, curl, tar)
# ------------------------------------------------------------------------------
sudo_cmd() {
    if [[ "$(id -u)" -eq 0 ]]; then
        run_cmd "$@"
    elif command -v sudo >/dev/null 2>&1; then
        run_cmd sudo "$@"
    else
        log_error "Root privileges or sudo required to run: $*"
        return 1
    fi
}

install_pkg() {
    local pkg="$1"
    case "$PKG_MGR" in
        apt)    sudo_cmd apt-get update -qq && sudo_cmd apt-get install -y -qq "$pkg" ;;
        pacman) sudo_cmd pacman -Sy --noconfirm --needed "$pkg" ;;
        dnf)    sudo_cmd dnf install -y "$pkg" ;;
        yum)    sudo_cmd yum install -y "$pkg" ;;
        zypper) sudo_cmd zypper --non-interactive install "$pkg" ;;
        apk)    sudo_cmd apk add --no-cache "$pkg" ;;
        brew)   run_cmd brew install "$pkg" ;;
        *)      return 1 ;;
    esac
}

ensure_base_deps() {
    for dep in git curl tar; do
        if ! command -v "$dep" >/dev/null 2>&1; then
            log_info "Installing base dependency: $dep"
            install_pkg "$dep"
        fi
    done
    run_cmd mkdir -p "$INSTALL_BIN_DIR" "$INSTALL_SHARE_DIR"
    export PATH="${INSTALL_BIN_DIR}:${PATH}"
}

# ------------------------------------------------------------------------------
# 3. Tool Installers
# ------------------------------------------------------------------------------
install_fzf() {
    if command -v fzf >/dev/null 2>&1; then
        log_ok "fzf is already installed ($(command -v fzf))"
        return 0
    fi
    log_info "Installing fzf..."
    if install_pkg fzf; then
        log_ok "fzf installed via ${PKG_MGR}"
        return 0
    fi

    log_info "Falling back to git installation for fzf..."
    local fzf_dir="${INSTALL_SHARE_DIR}/fzf"
    if [[ ! -d "$fzf_dir" ]]; then
        run_cmd git clone --depth 1 https://github.com/junegunn/fzf.git "$fzf_dir"
    fi
    run_cmd "${fzf_dir}/install" --bin
    run_cmd ln -sf "${fzf_dir}/bin/fzf" "${INSTALL_BIN_DIR}/fzf"
    log_ok "fzf installed to ${INSTALL_BIN_DIR}/fzf"
}

install_kubectx_kubens() {
    if command -v kubectx >/dev/null 2>&1 && command -v kubens >/dev/null 2>&1; then
        log_ok "kubectx & kubens already installed"
        return 0
    fi
    log_info "Installing kubectx and kubens..."
    local repo_dir="${INSTALL_SHARE_DIR}/kubectx"
    if [[ -d "$repo_dir/.git" ]]; then
        run_cmd git -C "$repo_dir" pull --ff-only
    else
        run_cmd rm -rf "$repo_dir"
        run_cmd git clone --depth 1 https://github.com/ahmetb/kubectx.git "$repo_dir"
    fi
    run_cmd ln -sf "${repo_dir}/kubectx" "${INSTALL_BIN_DIR}/kubectx"
    run_cmd ln -sf "${repo_dir}/kubens" "${INSTALL_BIN_DIR}/kubens"
    log_ok "kubectx and kubens installed to ${INSTALL_BIN_DIR}"
}

install_helm() {
    if command -v helm >/dev/null 2>&1; then
        log_ok "helm is already installed ($(command -v helm))"
        return 0
    fi
    log_info "Installing helm..."
    if [[ "$PKG_MGR" == "brew" || "$PKG_MGR" == "pacman" ]]; then
        if install_pkg helm; then
            log_ok "helm installed via ${PKG_MGR}"
            return 0
        fi
    fi

    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Would install helm via get-helm-3 script into ${INSTALL_BIN_DIR}"
    else
        curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | \
            HELM_INSTALL_DIR="$INSTALL_BIN_DIR" USE_SUDO="false" bash
        log_ok "helm installed to ${INSTALL_BIN_DIR}/helm"
    fi
}

install_k9s() {
    if command -v k9s >/dev/null 2>&1; then
        log_ok "k9s is already installed ($(command -v k9s))"
        return 0
    fi
    log_info "Installing k9s..."
    if [[ "$PKG_MGR" == "brew" || "$PKG_MGR" == "pacman" ]]; then
        if install_pkg k9s; then
            log_ok "k9s installed via ${PKG_MGR}"
            return 0
        fi
    fi

    local os_title
    if [[ "$OS" == "linux" ]]; then
        os_title="Linux"
    else
        os_title="Darwin"
    fi

    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Would download latest k9s_${os_title}_${ARCH_K9S}.tar.gz to ${INSTALL_BIN_DIR}/k9s"
        return 0
    fi

    local latest_tag
    latest_tag="$(curl -fsSL https://api.github.com/repos/derailed/k9s/releases/latest | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')"
    if [[ -z "$latest_tag" ]]; then
        log_error "Failed to fetch latest k9s version from GitHub"
        return 1
    fi

    local tarball_url="https://github.com/derailed/k9s/releases/download/${latest_tag}/k9s_${os_title}_${ARCH_K9S}.tar.gz"
    local tmp_dir
    tmp_dir="$(mktemp -d)"
    curl -fsSL "$tarball_url" -o "${tmp_dir}/k9s.tar.gz"
    tar -xzf "${tmp_dir}/k9s.tar.gz" -C "$tmp_dir" k9s
    install -m 0755 "${tmp_dir}/k9s" "${INSTALL_BIN_DIR}/k9s"
    rm -rf "$tmp_dir"
    log_ok "k9s (${latest_tag}) installed to ${INSTALL_BIN_DIR}/k9s"
}

install_kubetail() {
    if command -v kubetail >/dev/null 2>&1; then
        log_ok "kubetail is already installed ($(command -v kubetail))"
        return 0
    fi
    log_info "Installing kubetail..."
    local repo_dir="${INSTALL_SHARE_DIR}/kubetail"
    if [[ -d "$repo_dir/.git" ]]; then
        run_cmd git -C "$repo_dir" pull --ff-only
    else
        run_cmd rm -rf "$repo_dir"
        run_cmd git clone --depth 1 https://github.com/johanhaleby/kubetail.git "$repo_dir"
    fi
    run_cmd ln -sf "${repo_dir}/kubetail" "${INSTALL_BIN_DIR}/kubetail"
    log_ok "kubetail installed to ${INSTALL_BIN_DIR}/kubetail"
}

install_kube_ps1() {
    local repo_dir="${INSTALL_SHARE_DIR}/kube-ps1"
    if [[ -f "${repo_dir}/kube-ps1.sh" ]]; then
        log_ok "kube-ps1 is already installed (${repo_dir}/kube-ps1.sh)"
        return 0
    fi
    log_info "Installing kube-ps1..."
    run_cmd rm -rf "$repo_dir"
    run_cmd git clone --depth 1 https://github.com/jonmosco/kube-ps1.git "$repo_dir"
    log_ok "kube-ps1 installed to ${repo_dir}"
}

# ------------------------------------------------------------------------------
# 4. Shell RC Configuration (Bash, Zsh, Fish)
# ------------------------------------------------------------------------------
remove_block_from_file() {
    local rc_file="$1"
    [[ -f "$rc_file" ]] || return 0
    if grep -q "$MARKER_BEGIN" "$rc_file"; then
        if [[ "$DRY_RUN" == "true" ]]; then
            log_info "[DRY-RUN] Would remove existing kube-tools block from $rc_file"
        else
            local tmp_file="${rc_file}.kubetools.tmp"
            awk -v begin="$MARKER_BEGIN" -v end="$MARKER_END" '
                $0 == begin { skip=1; next }
                $0 == end   { skip=0; next }
                !skip       { print }
            ' "$rc_file" > "$tmp_file"
            mv "$tmp_file" "$rc_file"
        fi
    fi
}

configure_posix_rc() {
    local rc_file="$1"
    local shell_type="$2"

    remove_block_from_file "$rc_file"

    local prompt_line=""
    if [[ "$shell_type" == "bash" ]]; then
        prompt_line='if [[ "$PS1" != *"kube_ps1"* ]]; then PS1="\$(kube_ps1) $PS1"; fi'
    elif [[ "$shell_type" == "zsh" ]]; then
        prompt_line='if [[ "$PROMPT" != *"kube_ps1"* ]]; then PROMPT="\$(kube_ps1) $PROMPT"; fi'
    fi

    local block
    block="$(cat <<EOF
${MARKER_BEGIN}
export PATH="\${HOME}/.local/bin:\${PATH}"
alias kctx='kubectx'
alias kns='kubens'
if [ -f "${INSTALL_SHARE_DIR}/kube-ps1/kube-ps1.sh" ]; then
    source "${INSTALL_SHARE_DIR}/kube-ps1/kube-ps1.sh"
    ${prompt_line}
fi
${MARKER_END}
EOF
)"

    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Would update ${rc_file} with kctx/kns aliases and kube-ps1"
    else
        touch "$rc_file"
        printf "\n%s\n" "$block" >> "$rc_file"
        log_ok "Configured ${rc_file} (${shell_type})"
    fi
}

configure_fish_rc() {
    local fish_rc="${HOME}/.config/fish/config.fish"
    remove_block_from_file "$fish_rc"

    local block
    block="$(cat <<EOF
${MARKER_BEGIN}
fish_add_path -g "\$HOME/.local/bin"
alias kctx 'kubectx'
alias kns 'kubens'

function __kube_ps1_status
    if not set -q __KUBE_PS1_DISABLED; and command -sq kubectl
        set -l ctx (kubectl config current-context 2>/dev/null)
        if test -n "\$ctx"
            set -l ns (kubectl config view --minify --output 'jsonpath={..namespace}' 2>/dev/null)
            test -z "\$ns"; and set ns default
            echo -n "(\"\$ctx\":\"\$ns\") "
        end
    end
end
function kubeon; set -e __KUBE_PS1_DISABLED; end
function kubeoff; set -g __KUBE_PS1_DISABLED 1; end
${MARKER_END}
EOF
)"

    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Would update ${fish_rc} with kctx/kns aliases and kube-ps1 helpers"
    else
        mkdir -p "$(dirname "$fish_rc")"
        touch "$fish_rc"
        printf "\n%s\n" "$block" >> "$fish_rc"
        log_ok "Configured ${fish_rc} (fish)"
    fi
}

configure_shells() {
    log_info "Configuring shell aliases (kctx, kns) and kube-ps1..."

    # Always configure the detected primary shell, plus any existing shell RC files
    if [[ "$USER_SHELL" == "bash" || -f "${HOME}/.bashrc" ]]; then
        configure_posix_rc "${HOME}/.bashrc" "bash"
    fi

    if [[ "$USER_SHELL" == "zsh" || -f "${HOME}/.zshrc" ]]; then
        configure_posix_rc "${HOME}/.zshrc" "zsh"
    fi

    if [[ "$USER_SHELL" == "fish" || -f "${HOME}/.config/fish/config.fish" ]]; then
        configure_fish_rc
    fi
}

# ------------------------------------------------------------------------------
# 5. Uninstall / Rollback
# ------------------------------------------------------------------------------
uninstall_all() {
    log_info "Rolling back kube-tools installation..."
    remove_block_from_file "${HOME}/.bashrc"
    remove_block_from_file "${HOME}/.zshrc"
    remove_block_from_file "${HOME}/.config/fish/config.fish"

    for bin in kubectx kubens kubetail k9s helm fzf; do
        if [[ -L "${INSTALL_BIN_DIR}/${bin}" || -f "${INSTALL_BIN_DIR}/${bin}" ]]; then
            run_cmd rm -f "${INSTALL_BIN_DIR}/${bin}"
            log_ok "Removed ${INSTALL_BIN_DIR}/${bin}"
        fi
    done

    if [[ -d "$INSTALL_SHARE_DIR" ]]; then
        run_cmd rm -rf "$INSTALL_SHARE_DIR"
        log_ok "Removed ${INSTALL_SHARE_DIR}"
    fi
    log_ok "Rollback complete."
}

# ------------------------------------------------------------------------------
# Main Execution
# ------------------------------------------------------------------------------
main() {
    detect_environment

    if [[ "$UNINSTALL" == "true" ]]; then
        uninstall_all
        exit 0
    fi

    ensure_base_deps
    install_fzf
    install_kubectx_kubens
    install_helm
    install_k9s
    install_kubetail
    install_kube_ps1
    configure_shells

    printf "\n"
    log_ok "All tools installed and configured successfully!"
    log_info "Reload your shell to activate aliases (kctx, kns) and kube-ps1:"
    case "$USER_SHELL" in
        zsh)  printf "  source ~/.zshrc\n" ;;
        fish) printf "  source ~/.config/fish/config.fish\n" ;;
        *)    printf "  source ~/.bashrc\n" ;;
    esac
}

main "$@"
