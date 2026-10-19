#!/usr/bin/env bash
# ==============================================================================
# kube-tools: Centralized, verified installer & shell configurator for K8s tools
# Tools: fzf, kubectx/kubens, helm, k9s, kubetail, kube-ps1
# Repository: https://github.com/BernardoVillanova/kube-tools
# License: MIT
# ==============================================================================

set -euo pipefail

VERSION="1.4.0"
INSTALL_BIN_DIR="${HOME}/.local/bin"
INSTALL_SHARE_DIR="${HOME}/.local/share/kube-tools"
MANIFEST_FILE="${INSTALL_SHARE_DIR}/manifest.state"
MARKER_BEGIN="# >>> kube-tools initialize >>>"
MARKER_END="# <<< kube-tools initialize <<<"

# Pinned Toolchain Versions & Tags (Supply-Chain Security Pinning)
FZF_PINNED_TAG="${KUBE_TOOLS_FZF_VERSION:-v0.74.5}"
KUBECTX_PINNED_TAG="${KUBE_TOOLS_KUBECTX_VERSION:-v0.9.5}"
KUBETAIL_PINNED_TAG="${KUBE_TOOLS_KUBETAIL_VERSION:-1.6.22}"
KUBE_PS1_PINNED_TAG="${KUBE_TOOLS_KUBE_PS1_VERSION:-v1.0.0}"
HELM_PINNED_VERSION="${KUBE_TOOLS_HELM_VERSION:-v3.22.1}"
K9S_PINNED_VERSION="${KUBE_TOOLS_K9S_VERSION:-v0.51.0}"

# Pre-known SHA-256 digests for Helm (v3.22.1) - Portable across Bash 3.2+
get_pinned_helm_sha256() {
    local target="$1"
    case "$target" in
        linux-amd64)  printf "896cf63684a42a723d61c980369d6e588330927deb13676ca0d85006dd6da0ea" ;;
        linux-arm64)  printf "4c29e286b279d170fa048ddfc3e4e83dcd069ca9c52102766ba672d7149e694d" ;;
        darwin-amd64) printf "cf850a81b908f8eef0331e6b18776da2767bcac639ca84472311dad20008495c" ;;
        darwin-arm64) printf "e73da8a0b0d5193774fdff17ce6319c7436bb22ee229b45fd64f3c40368c753a" ;;
        *)            return 1 ;;
    esac
}

# Pre-known SHA-256 digests for k9s (v0.51.0) - Portable across Bash 3.2+
get_pinned_k9s_sha256() {
    local target="$1"
    case "$target" in
        Linux-amd64)  printf "c3752ad51a5a4015a113819c4eeb6e55a4d0e4b8e652494797532f6fc8161dd7" ;;
        Linux-arm64)  printf "3ee05c82e5f9198928a4e86133608ba6a2c10a2244d6a7789e820f78319d640c" ;;
        Darwin-amd64) printf "7e8802c57c45a0cd389e8fc38472243fe4cf48d8ad5957e189ce370e19e5eda0" ;;
        Darwin-arm64) printf "9b8c0e8f461e5d33aeee43a67f5ef4aff646a008a786887b8266cbb153c610cc" ;;
        *)            return 1 ;;
    esac
}

DRY_RUN=false
UNINSTALL=false
NON_INTERACTIVE=false
DOCTOR_MODE=false

# Auto-detect CLI language from locale (default: pt if LANG starts with pt, else en)
if [[ "${LANG:-}" == pt* || "${LC_ALL:-}" == pt* ]]; then
    CLI_LANG="pt"
else
    CLI_LANG="en"
fi

# Default Alias Configuration
ALIAS_KUBECTX="kctx"
ALIAS_KUBENS="kns"
ALIAS_KUBECTL=""
ALIAS_KUBETAIL=""
EXTRA_ALIASES=()
ENABLE_KUBE_PS1_PROMPT=true

# Colors & Formatting
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m'

log_info()  { printf "${BLUE}[INFO]${NC} %s\n" "$*"; }
log_ok()    { printf "${GREEN}[OK]${NC} %s\n" "$*"; }
log_warn()  { printf "${YELLOW}[WARN]${NC} %s\n" "$*"; }
log_error() { printf "${RED}[ERROR]${NC} %s\n" "$*" >&2; }

msg() {
    local en="$1"
    local pt="$2"
    if [[ "$CLI_LANG" == "pt" ]]; then
        printf "%s" "$pt"
    else
        printf "%s" "$en"
    fi
}

usage() {
    cat <<EOF
kube-tools v${VERSION} — Kubernetes CLI Toolchain Installer & Shell Configurator

Usage: $(basename "$0") [OPTIONS]

Options:
  -y, --yes          Non-interactive mode (install all missing tools & default aliases)
  --doctor, --check  Run environment, checksum, PATH, and tool health diagnostics
  --dry-run          Simulate installation and shell changes without mutating the system
  --uninstall        Remove kube-tools managed binaries, shared repos, and shell aliases
  --lang <en|pt>     Set interface language (default: auto-detected from \$LANG)
  -v, --version      Show version information
  -h, --help         Show this help message
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        -y|--yes|--non-interactive) NON_INTERACTIVE=true; shift ;;
        --doctor|--check)           DOCTOR_MODE=true; shift ;;
        --dry-run)                  DRY_RUN=true; shift ;;
        --uninstall|--rollback)     UNINSTALL=true; shift ;;
        --lang)
            if [[ $# -lt 2 ]]; then log_error "Missing argument for --lang"; exit 1; fi
            CLI_LANG="$2"; shift 2 ;;
        -v|--version)               printf "kube-tools v%s\n" "$VERSION"; exit 0 ;;
        -h|--help)                  usage; exit 0 ;;
        *) log_error "$(msg "Unknown option" "Opção desconhecida"): $1"; usage; exit 1 ;;
    esac
done

run_cmd() {
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] $(msg "Would execute" "Executaria"): $*"
    else
        "$@"
    fi
}

# ------------------------------------------------------------------------------
# 1. Security & Integrity Verification Helpers (SHA-256, Input & Path Guards)
# ------------------------------------------------------------------------------
curl_secure() {
    curl --proto '=https' --tlsv1.2 -fsSL "$@"
}

get_github_latest_release_tag() {
    local repo="$1"
    local tag=""
    # 1. Primary: HTTP 302 redirect location (zero REST API quota consumption)
    tag="$(curl_secure -I -o /dev/null -w '%{url_effective}' "https://github.com/${repo}/releases/latest" 2>/dev/null | sed -E 's#.*/tag/##')"
    if [[ "$tag" =~ ^v?[0-9]+\.[0-9]+\.[0-9]+(-[a-zA-Z0-9._-]+)?$ ]]; then
        printf "%s\n" "$tag"
        return 0
    fi

    # 2. Fallback: GitHub REST API if redirect resolution failed
    tag="$(curl_secure "https://api.github.com/repos/${repo}/releases/latest" 2>/dev/null | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')"
    if [[ "$tag" =~ ^v?[0-9]+\.[0-9]+\.[0-9]+(-[a-zA-Z0-9._-]+)?$ ]]; then
        printf "%s\n" "$tag"
        return 0
    fi

    return 1
}

is_valid_alias_name() {
    local name="$1"
    [[ "$name" =~ ^[a-zA-Z_][a-zA-Z0-9_-]*$ ]]
}

is_valid_alias_value() {
    local val="$1"
    # Reject empty values, newlines, or carriage returns
    [[ -n "$val" && "$val" != *$'\n'* && "$val" != *$'\r'* ]]
}

escape_single_quotes_posix() {
    local str="$1"
    # Safely escape ' as '\'' for POSIX single-quoted strings (portable across Bash 3.2 & 5+)
    printf "%s" "$str" | sed "s/'/'\\\\''/g"
}

escape_single_quotes_fish() {
    local str="$1"
    # Safely escape \ and ' for fish single-quoted strings (portable across Bash 3.2 & 5+)
    printf "%s" "$str" | sed "s/\\\\/\\\\\\\\/g; s/'/\\\\'/g"
}

is_safe_managed_path() {
    local target="$1"
    local base_dir="$2"
    # Reject empty, relative, or parent-traversal paths
    [[ -n "$target" && -n "$base_dir" ]] || return 1
    [[ "$target" == /* ]] || return 1
    [[ "$target" != *"/../"* && "$target" != *"/.." ]] || return 1
    # Must be strictly inside base_dir (not equal to base_dir or /)
    [[ "$target" == "${base_dir}/"* && "$target" != "${base_dir}/" ]] || return 1
    return 0
}

compute_sha256() {
    local file="$1"
    if command -v sha256sum >/dev/null 2>&1; then
        sha256sum "$file" | awk '{print $1}'
    elif command -v shasum >/dev/null 2>&1; then
        shasum -a 256 "$file" | awk '{print $1}'
    elif command -v openssl >/dev/null 2>&1; then
        openssl dgst -sha256 "$file" | awk '{print $NF}'
    else
        log_error "$(msg "No SHA-256 tool found (sha256sum, shasum, openssl)" "Nenhuma ferramenta SHA-256 encontrada")"
        return 1
    fi
}

verify_sha256() {
    local file="$1"
    local expected_hash="$2"

    # Fail-closed if expected_hash is missing or not a valid 64-hex SHA-256 digest
    if [[ ! "$expected_hash" =~ ^[a-fA-F0-9]{64}$ ]]; then
        log_error "$(msg "Invalid or empty expected SHA-256 digest for" "Hash SHA-256 esperado inválido ou vazio para") $(basename "$file")"
        return 1
    fi

    local actual_hash
    actual_hash="$(compute_sha256 "$file")"

    # Case-insensitive comparison via tr
    local norm_expected norm_actual
    norm_expected="$(printf "%s" "$expected_hash" | tr '[:upper:]' '[:lower:]')"
    norm_actual="$(printf "%s" "$actual_hash" | tr '[:upper:]' '[:lower:]')"

    if [[ "$norm_actual" != "$norm_expected" ]]; then
        log_error "$(msg "SHA-256 checksum mismatch for" "Falha na verificação SHA-256 de") $(basename "$file")!"
        log_error "  Expected: ${norm_expected}"
        log_error "  Actual:   ${norm_actual}"
        return 1
    fi
    log_ok "$(msg "SHA-256 checksum verified" "Checksum SHA-256 verificado"): ${norm_actual:0:16}..."
}

check_network_connectivity() {
    if ! command -v curl >/dev/null 2>&1; then
        return 0
    fi
    if curl_secure --connect-timeout 5 -I https://github.com >/dev/null 2>&1; then
        return 0
    elif curl_secure --connect-timeout 5 -I https://get.helm.sh >/dev/null 2>&1; then
        return 0
    else
        return 1
    fi
}

# ------------------------------------------------------------------------------
# 2. Environment & Installed Tools Detection
# ------------------------------------------------------------------------------
detect_environment() {
    OS_KERNEL="$(uname -s)"
    ARCH_RAW="$(uname -m)"

    case "$OS_KERNEL" in
        Linux*)  OS="linux" ;;
        Darwin*) OS="darwin" ;;
        *)       log_error "$(msg "Unsupported OS" "SO não suportado"): $OS_KERNEL"; exit 1 ;;
    esac

    case "$ARCH_RAW" in
        x86_64|amd64)   ARCH="amd64"; ARCH_K9S="amd64" ;;
        aarch64|arm64)  ARCH="arm64"; ARCH_K9S="arm64" ;;
        *)              log_error "$(msg "Unsupported architecture" "Arquitetura não suportada"): $ARCH_RAW"; exit 1 ;;
    esac

    DISTRO="unknown"
    if [[ "$OS" == "linux" && -f /etc/os-release ]]; then
        DISTRO="$(awk -F= '$1=="ID" {gsub(/"/, "", $2); print $2}' /etc/os-release 2>/dev/null || echo "unknown")"
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
    PATH_HAS_LOCAL_BIN=false
    if [[ ":${PATH}:" == *":${INSTALL_BIN_DIR}:"* ]]; then
        PATH_HAS_LOCAL_BIN=true
    fi
    export PATH="${INSTALL_BIN_DIR}:${PATH}"
}

get_tool_version() {
    local tool="$1"
    case "$tool" in
        fzf)      fzf --version 2>/dev/null | head -n1 | awk '{print $1}' || echo "installed" ;;
        kubectx)  kubectx --version 2>/dev/null | head -n1 || echo "installed" ;;
        helm)     helm version --short 2>/dev/null | head -n1 || echo "installed" ;;
        k9s)      k9s version -s 2>/dev/null | awk '/Version/ {print $2}' | head -n1 || echo "installed" ;;
        kubetail) kubetail --version 2>/dev/null | head -n1 | awk '{print $NF}' || echo "installed" ;;
        kubectl)  kubectl version --client -o yaml 2>/dev/null | awk '/gitVersion:/ {print $2}' | head -n1 || echo "installed" ;;
        *)        echo "installed" ;;
    esac
}

# Tool catalog
TOOL_KEYS=("fzf" "kubectx" "helm" "k9s" "kubetail" "kube-ps1")
TOOL_DESC_EN=(
    "fzf              (Interactive fuzzy finder for contexts & namespaces)"
    "kubectx & kubens (Fast switching between K8s contexts & namespaces)"
    "helm             (The Kubernetes Package Manager)"
    "k9s              (Terminal UI to interact with Kubernetes clusters)"
    "kubetail         (Tail logs from multiple Kubernetes pods at the same time)"
    "kube-ps1         (Kubernetes context and namespace status on shell prompt)"
)
TOOL_DESC_PT=(
    "fzf              (Busca interativa fuzzy p/ contextos e namespaces)"
    "kubectx & kubens (Alternância rápida de contexto e namespace)"
    "helm             (Gerenciador de pacotes do Kubernetes)"
    "k9s              (Terminal UI interativo para clusters Kubernetes)"
    "kubetail         (Agregador de logs de múltiplos pods em tempo real)"
    "kube-ps1         (Contexto e namespace atual no prompt do shell)"
)
TOOL_INSTALLED=(0 0 0 0 0 0)
TOOL_LOCATION=("" "" "" "" "" "")
TOOL_VERSION=("" "" "" "" "" "")
TOOL_SELECTED=(0 0 0 0 0 0)

check_installed_tools() {
    # 0: fzf
    if command -v fzf >/dev/null 2>&1; then
        TOOL_INSTALLED[0]=1
        TOOL_LOCATION[0]="$(command -v fzf)"
        TOOL_VERSION[0]="$(get_tool_version fzf)"
    fi

    # 1: kubectx & kubens
    if command -v kubectx >/dev/null 2>&1 && command -v kubens >/dev/null 2>&1; then
        TOOL_INSTALLED[1]=1
        TOOL_LOCATION[1]="$(command -v kubectx)"
        TOOL_VERSION[1]="$(get_tool_version kubectx)"
    fi

    # 2: helm
    if command -v helm >/dev/null 2>&1; then
        TOOL_INSTALLED[2]=1
        TOOL_LOCATION[2]="$(command -v helm)"
        TOOL_VERSION[2]="$(get_tool_version helm)"
    fi

    # 3: k9s
    if command -v k9s >/dev/null 2>&1; then
        TOOL_INSTALLED[3]=1
        TOOL_LOCATION[3]="$(command -v k9s)"
        TOOL_VERSION[3]="$(get_tool_version k9s)"
    fi

    # 4: kubetail
    if command -v kubetail >/dev/null 2>&1; then
        TOOL_INSTALLED[4]=1
        TOOL_LOCATION[4]="$(command -v kubetail)"
        TOOL_VERSION[4]="$(get_tool_version kubetail)"
    fi

    # 5: kube-ps1
    if [[ -f "${INSTALL_SHARE_DIR}/kube-ps1/kube-ps1.sh" ]]; then
        TOOL_INSTALLED[5]=1
        TOOL_LOCATION[5]="${INSTALL_SHARE_DIR}/kube-ps1/kube-ps1.sh"
        TOOL_VERSION[5]="script"
    elif [[ -f "/usr/share/kube-ps1/kube-ps1.sh" ]]; then
        TOOL_INSTALLED[5]=1
        TOOL_LOCATION[5]="/usr/share/kube-ps1/kube-ps1.sh"
        TOOL_VERSION[5]="script"
    fi

    # Pre-select tools that are NOT installed yet
    for i in "${!TOOL_KEYS[@]}"; do
        if [[ "${TOOL_INSTALLED[i]}" -eq 0 ]]; then
            TOOL_SELECTED[i]=1
        else
            TOOL_SELECTED[i]=0
        fi
    done
}

print_diagnostic_report() {
    printf "\n%b======================================================================%b\n" "${BOLD}${CYAN}" "${NC}"
    printf "%b  KUBE-TOOLS v%s — %s%b\n" "${BOLD}${CYAN}" "$VERSION" \
        "$(msg "Environment & Toolchain Audit" "Diagnóstico do Ambiente e Ferramentas")" "${NC}"
    printf "%b======================================================================%b\n" "${BOLD}${CYAN}" "${NC}"
    printf "  ${BOLD}%-20s${NC} %s (%s)\n" "$(msg "Operating System:" "Sistema Operacional:")" "$OS" "$DISTRO"
    printf "  ${BOLD}%-20s${NC} %s (%s)\n" "$(msg "Architecture:" "Arquitetura:")" "$ARCH" "$ARCH_RAW"
    printf "  ${BOLD}%-20s${NC} %s\n"      "$(msg "Package Manager:" "Gerenciador Pacotes:")" "$PKG_MGR"
    printf "  ${BOLD}%-20s${NC} %s\n"      "$(msg "Primary Shell:" "Shell Principal:")" "$USER_SHELL"

    if command -v kubectl >/dev/null 2>&1; then
        printf "  ${BOLD}%-20s${NC} ${GREEN}%s${NC} (%s)\n" "kubectl:" "$(get_tool_version kubectl)" "$(command -v kubectl)"
    else
        printf "  ${BOLD}%-20s${NC} ${YELLOW}%s${NC}\n" "kubectl:" "$(msg "Not found in PATH" "Não encontrado no PATH")"
    fi

    printf "%b----------------------------------------------------------------------%b\n" "${CYAN}" "${NC}"
    printf "  ${BOLD}%s:${NC}\n\n" "$(msg "Current Toolchain Status" "Status atual das ferramentas no sistema")"

    for i in "${!TOOL_KEYS[@]}"; do
        local key="${TOOL_KEYS[i]}"
        if [[ "${TOOL_INSTALLED[i]}" -eq 1 ]]; then
            printf "   ${GREEN}✔${NC} %-14s ${GREEN}%-16s${NC} %-12s ${DIM}(%s)${NC}\n" \
                "$key" "$(msg "[Installed]" "[Já instalado]")" "${TOOL_VERSION[i]}" "${TOOL_LOCATION[i]}"
        else
            printf "   ${YELLOW}✗${NC} %-14s ${YELLOW}%-16s${NC}\n" \
                "$key" "$(msg "[Not installed]" "[Não instalado]")"
        fi
    done
    printf "%b======================================================================%b\n\n" "${CYAN}" "${NC}"
}

run_doctor() {
    print_diagnostic_report
    log_info "$(msg "Running extended health & security checks..." "Executando verificações estendidas de saúde e segurança...")"

    # 1. Base dependencies
    for dep in git curl tar; do
        if command -v "$dep" >/dev/null 2>&1; then
            log_ok "$(msg "Base dependency present" "Dependência base presente"): $dep ($(command -v "$dep"))"
        else
            log_warn "$(msg "Missing base dependency" "Dependência base ausente"): $dep"
        fi
    done

    # 2. Checksum utility
    if command -v sha256sum >/dev/null 2>&1 || command -v shasum >/dev/null 2>&1 || command -v openssl >/dev/null 2>&1; then
        log_ok "$(msg "SHA-256 verification engine available" "Motor de verificação SHA-256 disponível")"
    else
        log_warn "$(msg "No SHA-256 utility found" "Utilitário SHA-256 não encontrado")"
    fi

    # 3. PATH check
    if [[ "$PATH_HAS_LOCAL_BIN" == "true" ]]; then
        log_ok "${INSTALL_BIN_DIR} $(msg "is in your PATH" "está presente no seu PATH")"
    else
        log_warn "${INSTALL_BIN_DIR} $(msg "is not in your current PATH yet (will be added to shell RC)" "ainda não está no PATH atual (será adicionado ao RC do shell)")"
    fi

    # 4. Network check
    if check_network_connectivity; then
        log_ok "$(msg "GitHub API & release endpoints reachable" "Conectividade com GitHub API e releases verificada")"
    else
        log_warn "$(msg "Could not reach GitHub API (check internet or rate limit)" "Não foi possível conectar à API do GitHub")"
    fi

    # 5. Shell RC markers
    for rc in "${HOME}/.bashrc" "${HOME}/.zshrc" "${HOME}/.config/fish/config.fish"; do
        if [[ -f "$rc" ]]; then
            if grep -q "$MARKER_BEGIN" "$rc"; then
                log_ok "$(msg "kube-tools block configured in" "Bloco kube-tools configurado em"): $rc"
            else
                log_info "$(msg "kube-tools block not yet added to" "Bloco kube-tools ainda não adicionado em"): $rc"
            fi
        fi
    done
}

# ------------------------------------------------------------------------------
# 3. Interactive Bash Form (Tools Selection + Aliases Customization)
# ------------------------------------------------------------------------------
interactive_tool_selector() {
    while true; do
        printf "${BOLD}1) %s:${NC}\n" \
            "$(msg "Select which tools to install/update" "Escolha quais ferramentas deseja instalar/atualizar")"
        printf "   ${DIM}(%s)${NC}\n\n" \
            "$(msg "Missing tools are pre-selected with [x]" "As ferramentas ausentes já vêm pré-selecionadas com [x]")"

        for i in "${!TOOL_KEYS[@]}"; do
            local num=$((i + 1))
            local mark=" "
            [[ "${TOOL_SELECTED[$i]}" -eq 1 ]] && mark="${GREEN}x${NC}"

            local status_tag=""
            if [[ "${TOOL_INSTALLED[$i]}" -eq 1 ]]; then
                status_tag="${DIM}$(msg "[installed]" "[instalado]")${NC}"
            else
                status_tag="${YELLOW}$(msg "[missing]" "[ausente]")${NC}"
            fi

            local desc="${TOOL_DESC_EN[$i]}"
            [[ "$CLI_LANG" == "pt" ]] && desc="${TOOL_DESC_PT[$i]}"

            printf "   [%b] %d) %s %b\n" "$mark" "$num" "$desc" "$status_tag"
        done

        printf "\n"
        printf "   ${BOLD}%s:${NC}\n" "$(msg "Form Controls" "Comandos do formulário")"
        printf "   • %s (ex: ${CYAN}1 3 5${NC})\n" \
            "$(msg "Type numbers to toggle individual tools" "Digite os números para marcar/desmarcar")"
        printf "   • ${CYAN}a${NC} = %s | ${CYAN}m${NC} = %s | ${CYAN}n${NC} = %s\n" \
            "$(msg "select all" "marcar todas")" "$(msg "missing only" "apenas ausentes")" "$(msg "none" "nenhuma")"
        printf "   • %s ${GREEN}ENTER${NC} %s\n\n" \
            "$(msg "Press" "Pressione")" "$(msg "(blank) to continue" "(em branco) para avançar")"

        local choice=""
        read -r -p "$(msg "Your choice [ENTER to confirm]: " "Sua opção [ENTER p/ confirmar]: ")" choice || break

        if [[ -z "$choice" ]]; then
            break
        elif [[ "$choice" == "a" || "$choice" == "A" ]]; then
            for i in "${!TOOL_KEYS[@]}"; do TOOL_SELECTED[i]=1; done
        elif [[ "$choice" == "n" || "$choice" == "N" ]]; then
            for i in "${!TOOL_KEYS[@]}"; do TOOL_SELECTED[i]=0; done
        elif [[ "$choice" == "m" || "$choice" == "M" ]]; then
            for i in "${!TOOL_KEYS[@]}"; do
                if [[ "${TOOL_INSTALLED[i]}" -eq 0 ]]; then
                    TOOL_SELECTED[i]=1
                else
                    TOOL_SELECTED[i]=0
                fi
            done
        else
            local cleaned="${choice//,/ }"
            for token in $cleaned; do
                if [[ "$token" =~ ^[1-6]$ ]]; then
                    local idx=$((token - 1))
                    if [[ "${TOOL_SELECTED[idx]}" -eq 1 ]]; then
                        TOOL_SELECTED[idx]=0
                    else
                        TOOL_SELECTED[idx]=1
                    fi
                else
                    log_warn "$(msg "Invalid option ignored" "Opção inválida ignorada"): $token"
                fi
            done
        fi
        printf "\n"
    done
}

interactive_alias_form() {
    printf "\n%b----------------------------------------------------------------------%b\n" "${CYAN}" "${NC}"
    printf "${BOLD}2) %s (${USER_SHELL}):${NC}\n\n" \
        "$(msg "Aliases & Prompt Configuration" "Configuração de Aliases e Prompt")"

    # kubectx alias
    local input_kctx=""
    read -r -p "   $(msg "Alias for 'kubectx' [default: ${ALIAS_KUBECTX} | '-' to disable]: " "Alias para 'kubectx' [padrão: ${ALIAS_KUBECTX} | '-' p/ desativar]: ")" input_kctx || true
    if [[ "$input_kctx" == "-" ]]; then
        ALIAS_KUBECTX=""
    elif [[ -n "$input_kctx" ]]; then
        if is_valid_alias_name "$input_kctx"; then
            ALIAS_KUBECTX="$input_kctx"
        else
            log_warn "$(msg "Invalid alias name ignored (use letters, digits, _, -)" "Nome de alias inválido ignorado (use letras, números, _, -)")"
        fi
    fi

    # kubens alias
    local input_kns=""
    read -r -p "   $(msg "Alias for 'kubens'  [default: ${ALIAS_KUBENS}  | '-' to disable]: " "Alias para 'kubens'  [padrão: ${ALIAS_KUBENS}  | '-' p/ desativar]: ")" input_kns || true
    if [[ "$input_kns" == "-" ]]; then
        ALIAS_KUBENS=""
    elif [[ -n "$input_kns" ]]; then
        if is_valid_alias_name "$input_kns"; then
            ALIAS_KUBENS="$input_kns"
        else
            log_warn "$(msg "Invalid alias name ignored (use letters, digits, _, -)" "Nome de alias inválido ignorado (use letras, números, _, -)")"
        fi
    fi

    # Optional alias for kubectl
    local input_k=""
    read -r -p "   $(msg "Create alias for 'kubectl'? (e.g. k) [ENTER to skip]: " "Deseja criar alias para 'kubectl'? (ex: k) [ENTER p/ pular]: ")" input_k || true
    if [[ -n "$input_k" && "$input_k" != "-" ]]; then
        if is_valid_alias_name "$input_k"; then
            ALIAS_KUBECTL="$input_k"
        else
            log_warn "$(msg "Invalid alias name ignored" "Nome de alias inválido ignorado"): $input_k"
        fi
    fi

    # Optional alias for kubetail
    local input_kt=""
    read -r -p "   $(msg "Create alias for 'kubetail'? (e.g. kt) [ENTER to skip]: " "Deseja criar alias para 'kubetail'? (ex: kt) [ENTER p/ pular]: ")" input_kt || true
    if [[ -n "$input_kt" && "$input_kt" != "-" ]]; then
        if is_valid_alias_name "$input_kt"; then
            ALIAS_KUBETAIL="$input_kt"
        else
            log_warn "$(msg "Invalid alias name ignored" "Nome de alias inválido ignorado"): $input_kt"
        fi
    fi

    # Custom user aliases loop
    printf "\n   ${DIM}%s${NC}\n" \
        "$(msg "Add custom aliases? (format: name=command)" "Deseja adicionar outros aliases personalizados? (formato: nome=comando)")"
    while true; do
        local custom_alias=""
        read -r -p "   $(msg "New alias [ENTER to finish]: " "Novo alias [ENTER p/ concluir]: ")" custom_alias || break
        [[ -z "$custom_alias" ]] && break
        if [[ "$custom_alias" == *"="* ]]; then
            local k="${custom_alias%%=*}"
            local v="${custom_alias#*=}"
            if is_valid_alias_name "$k" && is_valid_alias_value "$v"; then
                EXTRA_ALIASES+=("${k}=${v}")
                log_ok "$(msg "Alias added" "Alias adicionado"): ${k}=${v}"
            else
                log_warn "$(msg "Invalid alias name or command rejected" "Nome de alias ou comando inválido rejeitado"): $custom_alias"
            fi
        else
            log_warn "$(msg "Invalid format. Use name=command (e.g. kgp=kubectl get pods)" "Formato inválido. Use nome=comando (ex: kgp=kubectl get pods)")"
        fi
    done

    # kube-ps1 prompt toggle
    printf "\n"
    local input_ps1=""
    read -r -p "   $(msg "Enable kube-ps1 automatically in shell prompt? [Y/n]: " "Ativar kube-ps1 automaticamente no prompt do shell? [S/n]: ")" input_ps1 || true
    if [[ "$input_ps1" =~ ^[Nn]$ ]]; then
        ENABLE_KUBE_PS1_PROMPT=false
    else
        ENABLE_KUBE_PS1_PROMPT=true
    fi
}

confirm_summary() {
    printf "\n%b======================================================================%b\n" "${BOLD}${CYAN}" "${NC}"
    printf "%b  %s%b\n" "${BOLD}${CYAN}" "$(msg "Installation Summary" "Resumo da Instalação")" "${NC}"
    printf "%b======================================================================%b\n" "${BOLD}${CYAN}" "${NC}"

    printf "  ${BOLD}%s:${NC}\n" "$(msg "Selected Tools" "Ferramentas selecionadas")"
    local any_tool=false
    for i in "${!TOOL_KEYS[@]}"; do
        if [[ "${TOOL_SELECTED[i]}" -eq 1 ]]; then
            printf "   • %s\n" "${TOOL_KEYS[i]}"
            any_tool=true
        fi
    done
    [[ "$any_tool" == "false" ]] && printf "   • ${DIM}%s${NC}\n" "$(msg "(No tools will be installed)" "(Nenhuma ferramenta será instalada)")"

    printf "\n  ${BOLD}%s:${NC}\n" "$(msg "Configured Aliases" "Aliases que serão configurados")"
    [[ -n "$ALIAS_KUBECTX" ]]  && printf "   • %s -> kubectx\n" "$ALIAS_KUBECTX"
    [[ -n "$ALIAS_KUBENS" ]]   && printf "   • %s -> kubens\n" "$ALIAS_KUBENS"
    [[ -n "$ALIAS_KUBECTL" ]]  && printf "   • %s -> kubectl\n" "$ALIAS_KUBECTL"
    [[ -n "$ALIAS_KUBETAIL" ]] && printf "   • %s -> kubetail\n" "$ALIAS_KUBETAIL"
    if [[ ${#EXTRA_ALIASES[@]} -gt 0 ]]; then
        for extra in "${EXTRA_ALIASES[@]}"; do
            local k="${extra%%=*}"
            local v="${extra#*=}"
            printf "   • %s -> %s\n" "$k" "$v"
        done
    fi

    local ps1_state
    if [[ "$ENABLE_KUBE_PS1_PROMPT" == "true" ]]; then
        ps1_state="$(msg "Enabled" "Ativado")"
    else
        ps1_state="$(msg "Disabled" "Desativado")"
    fi
    printf "\n  ${BOLD}Prompt kube-ps1:${NC} %s\n" "$ps1_state"
    printf "%b======================================================================%b\n\n" "${CYAN}" "${NC}"

    local confirm=""
    read -r -p "$(msg "Confirm and apply changes? [Y/n]: " "Confirmar e aplicar configurações? [S/n]: ")" confirm || true
    if [[ "$confirm" =~ ^[Nn]$ ]]; then
        log_warn "$(msg "Operation cancelled by user." "Operação cancelada pelo usuário.")"
        exit 0
    fi
}

# ------------------------------------------------------------------------------
# 4. Privilege & Package Helpers
# ------------------------------------------------------------------------------
sudo_cmd() {
    if [[ "$(id -u)" -eq 0 ]]; then
        run_cmd "$@"
    elif command -v sudo >/dev/null 2>&1; then
        run_cmd sudo "$@"
    else
        log_error "$(msg "Root or sudo privileges required for" "Permissão de root ou sudo necessária para"): $*"
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
            log_info "$(msg "Installing base dependency" "Instalando dependência base"): $dep"
            install_pkg "$dep"
        fi
    done
    run_cmd mkdir -p "$INSTALL_BIN_DIR" "$INSTALL_SHARE_DIR"
}

record_manifest() {
    local entry="$1"
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] $(msg "Would record in manifest" "Registraria no manifesto"): $entry"
        return 0
    fi
    mkdir -p "$INSTALL_SHARE_DIR"
    touch "$MANIFEST_FILE"
    if ! grep -qxF "$entry" "$MANIFEST_FILE" 2>/dev/null; then
        printf "%s\n" "$entry" >> "$MANIFEST_FILE"
    fi
}

# ------------------------------------------------------------------------------
# 5. Individual Tool Installers (with SHA-256 Checksum & Manifest Tracking)
# ------------------------------------------------------------------------------
install_fzf() {
    local pre_installed="${TOOL_INSTALLED[0]}"
    log_info "$(msg "Installing fzf..." "Instalando fzf...")"
    if install_pkg fzf; then
        [[ "$pre_installed" -eq 0 ]] && record_manifest "pkg:${PKG_MGR}:fzf"
        log_ok "fzf $(msg "installed via" "instalado via") ${PKG_MGR}"
        return 0
    fi

    log_info "$(msg "Falling back to git installer for fzf (pinned tag ${FZF_PINNED_TAG})..." "Usando fallback via git para fzf (tag fixada ${FZF_PINNED_TAG})...")"
    local fzf_dir="${INSTALL_SHARE_DIR}/fzf"
    if [[ -d "$fzf_dir/.git" ]]; then
        run_cmd git -C "$fzf_dir" fetch --depth 1 origin tag "$FZF_PINNED_TAG"
        run_cmd git -C "$fzf_dir" -c advice.detachedHead=false checkout -q "$FZF_PINNED_TAG"
    else
        run_cmd rm -rf "$fzf_dir"
        run_cmd git clone --depth 1 --branch "$FZF_PINNED_TAG" https://github.com/junegunn/fzf.git "$fzf_dir"
    fi
    run_cmd "${fzf_dir}/install" --bin --no-update-rc --no-completion --no-key-bindings
    run_cmd ln -sf "${fzf_dir}/bin/fzf" "${INSTALL_BIN_DIR}/fzf"
    [[ "$pre_installed" -eq 0 ]] && record_manifest "file:${INSTALL_BIN_DIR}/fzf"
    record_manifest "dir:${fzf_dir}"
    log_ok "fzf (${FZF_PINNED_TAG}) -> ${INSTALL_BIN_DIR}/fzf"
}

install_kubectx_kubens() {
    local pre_installed="${TOOL_INSTALLED[1]}"
    log_info "$(msg "Installing kubectx & kubens (pinned tag ${KUBECTX_PINNED_TAG})..." "Instalando kubectx e kubens (tag fixada ${KUBECTX_PINNED_TAG})...")"
    local repo_dir="${INSTALL_SHARE_DIR}/kubectx"
    if [[ -d "$repo_dir/.git" ]]; then
        run_cmd git -C "$repo_dir" fetch --depth 1 origin tag "$KUBECTX_PINNED_TAG"
        run_cmd git -C "$repo_dir" -c advice.detachedHead=false checkout -q "$KUBECTX_PINNED_TAG"
    else
        run_cmd rm -rf "$repo_dir"
        run_cmd git clone --depth 1 --branch "$KUBECTX_PINNED_TAG" https://github.com/ahmetb/kubectx.git "$repo_dir"
    fi
    run_cmd ln -sf "${repo_dir}/kubectx" "${INSTALL_BIN_DIR}/kubectx"
    run_cmd ln -sf "${repo_dir}/kubens" "${INSTALL_BIN_DIR}/kubens"
    if [[ "$pre_installed" -eq 0 ]]; then
        record_manifest "file:${INSTALL_BIN_DIR}/kubectx"
        record_manifest "file:${INSTALL_BIN_DIR}/kubens"
    fi
    record_manifest "dir:${repo_dir}"
    log_ok "kubectx & kubens (${KUBECTX_PINNED_TAG}) -> ${INSTALL_BIN_DIR}"
}

install_helm() {
    local pre_installed="${TOOL_INSTALLED[2]}"
    log_info "$(msg "Installing helm..." "Instalando helm...")"
    if [[ "$PKG_MGR" == "brew" || "$PKG_MGR" == "pacman" ]]; then
        if install_pkg helm; then
            [[ "$pre_installed" -eq 0 ]] && record_manifest "pkg:${PKG_MGR}:helm"
            log_ok "helm $(msg "installed via" "instalado via") ${PKG_MGR}"
            return 0
        fi
    fi

    local helm_version="$HELM_PINNED_VERSION"
    if [[ -n "${KUBE_TOOLS_HELM_VERSION:-}" ]]; then
        if [[ "$KUBE_TOOLS_HELM_VERSION" == "latest" ]]; then
            helm_version="$(get_github_latest_release_tag "helm/helm" || echo "")"
            if [[ ! "$helm_version" =~ ^v?[0-9]+\.[0-9]+\.[0-9]+(-[a-zA-Z0-9._-]+)?$ ]]; then
                log_error "$(msg "Could not resolve latest Helm release tag" "Não foi possível obter a última tag de release do Helm")"
                return 1
            fi
        else
            helm_version="$KUBE_TOOLS_HELM_VERSION"
        fi
    fi

    local archive_name="helm-${helm_version}-${OS}-${ARCH}.tar.gz"

    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] $(msg "Would download & verify SHA-256 for" "Baixaria e verificaria SHA-256 de") ${archive_name} (${helm_version}) -> ${INSTALL_BIN_DIR}/helm"
        return 0
    fi

    local expected_sha="${KUBE_TOOLS_HELM_SHA256:-}"
    if [[ -z "$expected_sha" && "$helm_version" == "$HELM_PINNED_VERSION" ]]; then
        expected_sha="$(get_pinned_helm_sha256 "${OS}-${ARCH}" || echo "")"
    fi

    local tmp_dir
    tmp_dir="$(umask 077 && mktemp -d)"

    local primary_url="https://get.helm.sh/${archive_name}"
    local fallback_url="https://github.com/helm/helm/releases/download/${helm_version}/${archive_name}"

    if ! curl_secure "$primary_url" -o "${tmp_dir}/${archive_name}" 2>/dev/null; then
        log_info "$(msg "Retrying Helm download from GitHub releases..." "Tentando download do Helm via GitHub releases...")"
        if ! curl_secure "$fallback_url" -o "${tmp_dir}/${archive_name}"; then
            rm -rf "$tmp_dir"
            log_error "$(msg "Failed to download Helm release archive" "Falha ao baixar pacote de release do Helm")"
            return 1
        fi
    fi

    if [[ -z "$expected_sha" ]]; then
        log_warn "$(msg "Using remote sha256sum for unpinned Helm version" "Usando sha256sum remoto para versão não fixada do Helm")"
        if ! curl_secure "https://get.helm.sh/${archive_name}.sha256sum" -o "${tmp_dir}/helm.sha256" 2>/dev/null && \
           ! curl_secure "${fallback_url}.sha256sum" -o "${tmp_dir}/helm.sha256" 2>/dev/null; then
            rm -rf "$tmp_dir"
            log_error "$(msg "Failed to obtain SHA-256 checksum for Helm" "Falha ao obter checksum SHA-256 do Helm")"
            return 1
        fi
        expected_sha="$(awk '{print $1}' "${tmp_dir}/helm.sha256" | head -n1)"
    fi

    if ! verify_sha256 "${tmp_dir}/${archive_name}" "$expected_sha"; then
        rm -rf "$tmp_dir"
        return 1
    fi

    if ! tar -xzf "${tmp_dir}/${archive_name}" -C "$tmp_dir" "${OS}-${ARCH}/helm" || \
       ! install -m 0755 "${tmp_dir}/${OS}-${ARCH}/helm" "${INSTALL_BIN_DIR}/helm"; then
        rm -rf "$tmp_dir"
        log_error "$(msg "Failed to extract or install Helm binary" "Falha ao extrair ou instalar binário do Helm")"
        return 1
    fi

    rm -rf "$tmp_dir"
    [[ "$pre_installed" -eq 0 ]] && record_manifest "file:${INSTALL_BIN_DIR}/helm"
    log_ok "helm (${helm_version}) -> ${INSTALL_BIN_DIR}/helm"
}

install_k9s() {
    local pre_installed="${TOOL_INSTALLED[3]}"
    log_info "$(msg "Installing k9s..." "Instalando k9s...")"
    if [[ "$PKG_MGR" == "brew" || "$PKG_MGR" == "pacman" ]]; then
        if install_pkg k9s; then
            [[ "$pre_installed" -eq 0 ]] && record_manifest "pkg:${PKG_MGR}:k9s"
            log_ok "k9s $(msg "installed via" "instalado via") ${PKG_MGR}"
            return 0
        fi
    fi

    local os_title
    [[ "$OS" == "linux" ]] && os_title="Linux" || os_title="Darwin"
    local archive_name="k9s_${os_title}_${ARCH_K9S}.tar.gz"

    local k9s_version="$K9S_PINNED_VERSION"
    if [[ -n "${KUBE_TOOLS_K9S_VERSION:-}" ]]; then
        if [[ "$KUBE_TOOLS_K9S_VERSION" == "latest" ]]; then
            k9s_version="$(get_github_latest_release_tag "derailed/k9s" || echo "")"
            if [[ ! "$k9s_version" =~ ^v?[0-9]+\.[0-9]+\.[0-9]+(-[a-zA-Z0-9._-]+)?$ ]]; then
                log_error "$(msg "Could not resolve latest k9s release tag" "Não foi possível obter a última tag de release do k9s")"
                return 1
            fi
        else
            k9s_version="$KUBE_TOOLS_K9S_VERSION"
        fi
    fi

    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] $(msg "Would download & verify SHA-256 for" "Baixaria e verificaria SHA-256 de") ${archive_name} (${k9s_version}) -> ${INSTALL_BIN_DIR}/k9s"
        return 0
    fi

    local base_url="https://github.com/derailed/k9s/releases/download/${k9s_version}"
    local tmp_dir
    tmp_dir="$(umask 077 && mktemp -d)"

    if ! curl_secure "${base_url}/${archive_name}" -o "${tmp_dir}/${archive_name}"; then
        rm -rf "$tmp_dir"
        log_error "$(msg "Failed to download k9s release archive" "Falha ao baixar pacote de release do k9s")"
        return 1
    fi

    local expected_sha="${KUBE_TOOLS_K9S_SHA256:-}"
    if [[ -z "$expected_sha" && "$k9s_version" == "$K9S_PINNED_VERSION" ]]; then
        expected_sha="$(get_pinned_k9s_sha256 "${os_title}-${ARCH_K9S}" || echo "")"
    fi

    if [[ -z "$expected_sha" ]]; then
        log_warn "$(msg "Using release checksums file for unpinned k9s version" "Usando arquivo de checksum da release para versão não fixada do k9s")"
        if ! curl_secure "${base_url}/checksums.sha256" -o "${tmp_dir}/checksums.txt" 2>/dev/null && \
           ! curl_secure "${base_url}/checksums.txt" -o "${tmp_dir}/checksums.txt" 2>/dev/null; then
            rm -rf "$tmp_dir"
            log_error "$(msg "Failed to download k9s checksums file" "Falha ao baixar arquivo de checksums do k9s")"
            return 1
        fi
        expected_sha="$(awk -v f="$archive_name" '$2 == f {print $1}' "${tmp_dir}/checksums.txt" | head -n1)"
    fi

    if ! verify_sha256 "${tmp_dir}/${archive_name}" "$expected_sha"; then
        rm -rf "$tmp_dir"
        return 1
    fi

    if ! tar -xzf "${tmp_dir}/${archive_name}" -C "$tmp_dir" k9s || \
       ! install -m 0755 "${tmp_dir}/k9s" "${INSTALL_BIN_DIR}/k9s"; then
        rm -rf "$tmp_dir"
        log_error "$(msg "Failed to extract or install k9s binary" "Falha ao extrair ou instalar binário do k9s")"
        return 1
    fi

    rm -rf "$tmp_dir"
    [[ "$pre_installed" -eq 0 ]] && record_manifest "file:${INSTALL_BIN_DIR}/k9s"
    log_ok "k9s (${k9s_version}) -> ${INSTALL_BIN_DIR}/k9s"
}

install_kubetail() {
    local pre_installed="${TOOL_INSTALLED[4]}"
    log_info "$(msg "Installing kubetail (pinned tag ${KUBETAIL_PINNED_TAG})..." "Instalando kubetail (tag fixada ${KUBETAIL_PINNED_TAG})...")"
    local repo_dir="${INSTALL_SHARE_DIR}/kubetail"
    if [[ -d "$repo_dir/.git" ]]; then
        run_cmd git -C "$repo_dir" fetch --depth 1 origin tag "$KUBETAIL_PINNED_TAG"
        run_cmd git -C "$repo_dir" -c advice.detachedHead=false checkout -q "$KUBETAIL_PINNED_TAG"
    else
        run_cmd rm -rf "$repo_dir"
        run_cmd git clone --depth 1 --branch "$KUBETAIL_PINNED_TAG" https://github.com/johanhaleby/kubetail.git "$repo_dir"
    fi
    run_cmd ln -sf "${repo_dir}/kubetail" "${INSTALL_BIN_DIR}/kubetail"
    [[ "$pre_installed" -eq 0 ]] && record_manifest "file:${INSTALL_BIN_DIR}/kubetail"
    record_manifest "dir:${repo_dir}"
    log_ok "kubetail (${KUBETAIL_PINNED_TAG}) -> ${INSTALL_BIN_DIR}/kubetail"
}

install_kube_ps1() {
    local pre_installed="${TOOL_INSTALLED[5]}"
    log_info "$(msg "Installing kube-ps1 (pinned tag ${KUBE_PS1_PINNED_TAG})..." "Instalando kube-ps1 (tag fixada ${KUBE_PS1_PINNED_TAG})...")"
    local repo_dir="${INSTALL_SHARE_DIR}/kube-ps1"
    if [[ -d "$repo_dir/.git" ]]; then
        run_cmd git -C "$repo_dir" fetch --depth 1 origin tag "$KUBE_PS1_PINNED_TAG"
        run_cmd git -C "$repo_dir" -c advice.detachedHead=false checkout -q "$KUBE_PS1_PINNED_TAG"
    else
        run_cmd rm -rf "$repo_dir"
        run_cmd git clone --depth 1 --branch "$KUBE_PS1_PINNED_TAG" https://github.com/jonmosco/kube-ps1.git "$repo_dir"
    fi
    [[ "$pre_installed" -eq 0 ]] && record_manifest "dir:${repo_dir}"
    log_ok "kube-ps1 (${KUBE_PS1_PINNED_TAG}) -> ${repo_dir}"
}

run_selected_installers() {
    [[ "${TOOL_SELECTED[0]}" -eq 1 ]] && install_fzf
    [[ "${TOOL_SELECTED[1]}" -eq 1 ]] && install_kubectx_kubens
    [[ "${TOOL_SELECTED[2]}" -eq 1 ]] && install_helm
    [[ "${TOOL_SELECTED[3]}" -eq 1 ]] && install_k9s
    [[ "${TOOL_SELECTED[4]}" -eq 1 ]] && install_kubetail
    [[ "${TOOL_SELECTED[5]}" -eq 1 ]] && install_kube_ps1
    return 0
}

# ------------------------------------------------------------------------------
# 6. Shell RC Configuration (Bash, Zsh, Fish)
# ------------------------------------------------------------------------------
remove_block_from_file() {
    local rc_file="$1"
    [[ -f "$rc_file" ]] || return 0
    if grep -q "$MARKER_BEGIN" "$rc_file"; then
        if [[ "$DRY_RUN" == "true" ]]; then
            log_info "[DRY-RUN] $(msg "Would remove previous block from" "Removeria bloco anterior de") $rc_file"
        else
            local tmp_file
            tmp_file="$(umask 077 && mktemp)"
            if awk -v begin="$MARKER_BEGIN" -v end="$MARKER_END" '
                $0 == begin { skip=1; next }
                $0 == end   { skip=0; next }
                !skip       { print }
            ' "$rc_file" > "$tmp_file"; then
                # Write in-place to preserve symlinks (e.g., Stow/Chezmoi dotfiles) and permissions
                cat "$tmp_file" > "$rc_file"
            fi
            rm -f "$tmp_file"
        fi
    fi
}

build_posix_aliases() {
    local lines=""
    if [[ -n "$ALIAS_KUBECTX" ]] && is_valid_alias_name "$ALIAS_KUBECTX"; then
        lines+="alias ${ALIAS_KUBECTX}='kubectx'"$'\n'
    fi
    if [[ -n "$ALIAS_KUBENS" ]] && is_valid_alias_name "$ALIAS_KUBENS"; then
        lines+="alias ${ALIAS_KUBENS}='kubens'"$'\n'
    fi
    if [[ -n "$ALIAS_KUBECTL" ]] && is_valid_alias_name "$ALIAS_KUBECTL"; then
        lines+="alias ${ALIAS_KUBECTL}='kubectl'"$'\n'
    fi
    if [[ -n "$ALIAS_KUBETAIL" ]] && is_valid_alias_name "$ALIAS_KUBETAIL"; then
        lines+="alias ${ALIAS_KUBETAIL}='kubetail'"$'\n'
    fi
    if [[ ${#EXTRA_ALIASES[@]} -gt 0 ]]; then
        for extra in "${EXTRA_ALIASES[@]}"; do
            local k="${extra%%=*}"
            local v="${extra#*=}"
            if is_valid_alias_name "$k" && is_valid_alias_value "$v"; then
                local esc_v
                esc_v="$(escape_single_quotes_posix "$v")"
                lines+="alias ${k}='${esc_v}'"$'\n'
            fi
        done
    fi
    printf "%s" "$lines"
}

build_fish_aliases() {
    local lines=""
    if [[ -n "$ALIAS_KUBECTX" ]] && is_valid_alias_name "$ALIAS_KUBECTX"; then
        lines+="alias ${ALIAS_KUBECTX} 'kubectx'"$'\n'
    fi
    if [[ -n "$ALIAS_KUBENS" ]] && is_valid_alias_name "$ALIAS_KUBENS"; then
        lines+="alias ${ALIAS_KUBENS} 'kubens'"$'\n'
    fi
    if [[ -n "$ALIAS_KUBECTL" ]] && is_valid_alias_name "$ALIAS_KUBECTL"; then
        lines+="alias ${ALIAS_KUBECTL} 'kubectl'"$'\n'
    fi
    if [[ -n "$ALIAS_KUBETAIL" ]] && is_valid_alias_name "$ALIAS_KUBETAIL"; then
        lines+="alias ${ALIAS_KUBETAIL} 'kubetail'"$'\n'
    fi
    if [[ ${#EXTRA_ALIASES[@]} -gt 0 ]]; then
        for extra in "${EXTRA_ALIASES[@]}"; do
            local k="${extra%%=*}"
            local v="${extra#*=}"
            if is_valid_alias_name "$k" && is_valid_alias_value "$v"; then
                local esc_v
                esc_v="$(escape_single_quotes_fish "$v")"
                lines+="alias ${k} '${esc_v}'"$'\n'
            fi
        done
    fi
    printf "%s" "$lines"
}

configure_posix_rc() {
    local rc_file="$1"
    local shell_type="$2"

    remove_block_from_file "$rc_file"

    local prompt_line=""
    if [[ "$ENABLE_KUBE_PS1_PROMPT" == "true" ]]; then
        if [[ "$shell_type" == "bash" ]]; then
            # shellcheck disable=SC2016
            prompt_line='if [[ "$PS1" != *"kube_ps1"* ]]; then PS1="\$(kube_ps1) $PS1"; fi'
        elif [[ "$shell_type" == "zsh" ]]; then
            # shellcheck disable=SC2016
            prompt_line='if [[ "$PROMPT" != *"kube_ps1"* ]]; then PROMPT="\$(kube_ps1) $PROMPT"; fi'
        fi
    fi

    local alias_lines
    alias_lines="$(build_posix_aliases)"

    local footer
    footer="$(cat <<EOF
if [ -f "${INSTALL_SHARE_DIR}/kube-ps1/kube-ps1.sh" ]; then
    source "${INSTALL_SHARE_DIR}/kube-ps1/kube-ps1.sh"
    ${prompt_line}
fi
${MARKER_END}
EOF
)"

    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] $(msg "Would update" "Atualizaria") ${rc_file} (${shell_type})"
    else
        touch "$rc_file"
        printf "\n%s\nexport PATH=\"\${HOME}/.local/bin:\${PATH}\"\n%s%s\n" \
            "$MARKER_BEGIN" "$alias_lines" "$footer" >> "$rc_file"
        log_ok "$(msg "Configured" "Configurado") ${rc_file} (${shell_type})"
    fi
}

configure_fish_rc() {
    local fish_rc="${HOME}/.config/fish/config.fish"
    remove_block_from_file "$fish_rc"

    local alias_lines
    alias_lines="$(build_fish_aliases)"

    local footer
    footer="$(cat <<EOF
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
        log_info "[DRY-RUN] $(msg "Would update" "Atualizaria") ${fish_rc} (fish)"
    else
        mkdir -p "$(dirname "$fish_rc")"
        touch "$fish_rc"
        printf "\n%s\nfish_add_path -g \"\$HOME/.local/bin\"\n%s%s\n" \
            "$MARKER_BEGIN" "$alias_lines" "$footer" >> "$fish_rc"
        log_ok "$(msg "Configured" "Configurado") ${fish_rc} (fish)"
    fi
}

configure_shells() {
    log_info "$(msg "Applying shell and alias configurations..." "Aplicando configurações de shell e aliases...")"

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
# 7. Uninstall / Rollback (Strictly Scoped & Path-Confined by Manifest State)
# ------------------------------------------------------------------------------
uninstall_pkg() {
    local mgr="$1"
    local pkg="$2"
    case "$mgr" in
        apt)    sudo_cmd apt-get remove -y "$pkg" ;;
        pacman) sudo_cmd pacman -Rns --noconfirm "$pkg" ;;
        dnf)    sudo_cmd dnf remove -y "$pkg" ;;
        yum)    sudo_cmd yum remove -y "$pkg" ;;
        zypper) sudo_cmd zypper --non-interactive remove "$pkg" ;;
        apk)    sudo_cmd apk del "$pkg" ;;
        brew)   run_cmd brew uninstall "$pkg" ;;
        *)      return 1 ;;
    esac
}

uninstall_all() {
    log_info "$(msg "Rolling back kube-tools installation (strictly manifest-tracked items)..." "Revertendo instalação do kube-tools (apenas itens rastreados no manifesto)...")"
    remove_block_from_file "${HOME}/.bashrc"
    remove_block_from_file "${HOME}/.zshrc"
    remove_block_from_file "${HOME}/.config/fish/config.fish"

    if [[ -f "$MANIFEST_FILE" ]]; then
        while IFS= read -r entry || [[ -n "$entry" ]]; do
            [[ -z "$entry" ]] && continue
            local kind="${entry%%:*}"
            local rest="${entry#*:}"
            case "$kind" in
                file)
                    if is_safe_managed_path "$rest" "$INSTALL_BIN_DIR"; then
                        if [[ -L "$rest" || -f "$rest" ]]; then
                            run_cmd rm -f "$rest"
                            log_ok "$(msg "Removed tracked binary" "Binário rastreado removido"): $rest"
                        fi
                    else
                        log_warn "$(msg "Skipped unsafe manifest file path" "Caminho de arquivo inseguro no manifesto ignorado"): $rest"
                    fi
                    ;;
                dir)
                    if is_safe_managed_path "$rest" "$INSTALL_SHARE_DIR"; then
                        if [[ -d "$rest" ]]; then
                            run_cmd rm -rf "$rest"
                            log_ok "$(msg "Removed tracked directory" "Diretório rastreado removido"): $rest"
                        fi
                    else
                        log_warn "$(msg "Skipped unsafe manifest directory path" "Caminho de diretório inseguro no manifesto ignorado"): $rest"
                    fi
                    ;;
                pkg)
                    local mgr="${rest%%:*}"
                    local pkg="${rest#*:}"
                    if [[ "$mgr" =~ ^(apt|pacman|dnf|yum|zypper|apk|brew)$ ]] && [[ "$pkg" =~ ^(fzf|helm|k9s)$ ]]; then
                        log_info "$(msg "Removing package installed by kube-tools" "Removendo pacote instalado pelo kube-tools"): ${pkg} (${mgr})"
                        uninstall_pkg "$mgr" "$pkg" || log_warn "$(msg "Could not auto-remove package" "Não foi possível remover pacote automaticamente"): $pkg"
                    else
                        log_warn "$(msg "Skipped untrusted package entry in manifest" "Entrada de pacote não confiável ignorada no manifesto"): $rest"
                    fi
                    ;;
            esac
        done < "$MANIFEST_FILE"
        run_cmd rm -f "$MANIFEST_FILE"
    else
        log_info "$(msg "No manifest.state found — no pre-existing binaries were touched." "Nenhum manifest.state encontrado — nenhum binário pré-existente foi tocado.")"
    fi

    # Remove share dir if empty
    if [[ -d "$INSTALL_SHARE_DIR" ]] && [[ -z "$(ls -A "$INSTALL_SHARE_DIR" 2>/dev/null)" ]]; then
        run_cmd rmdir "$INSTALL_SHARE_DIR"
    fi

    log_ok "$(msg "Rollback completed safely (pre-existing tools preserved)." "Rollback concluído com segurança (ferramentas pré-existentes preservadas).")"
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

    check_installed_tools

    if [[ "$DOCTOR_MODE" == "true" ]]; then
        run_doctor
        exit 0
    fi

    print_diagnostic_report

    if [[ "$NON_INTERACTIVE" == "false" ]]; then
        interactive_tool_selector
        interactive_alias_form
        confirm_summary
    else
        log_info "$(msg "Non-interactive mode: installing missing tools with default aliases (kctx, kns)." "Modo não-interativo ativo: instalando ferramentas ausentes com aliases padrão (kctx, kns).")"
    fi

    ensure_base_deps
    run_selected_installers
    configure_shells

    printf "\n"
    log_ok "$(msg "All operations completed successfully!" "Processo finalizado com sucesso!")"
    log_info "$(msg "Reload your shell to activate aliases:" "Recarregue seu shell para ativar os aliases:")"
    case "$USER_SHELL" in
        zsh)  printf "  source ~/.zshrc\n" ;;
        fish) printf "  source ~/.config/fish/config.fish\n" ;;
        *)    printf "  source ~/.bashrc\n" ;;
    esac
}

main "$@"
