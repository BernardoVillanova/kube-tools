#!/usr/bin/env bash
# ==============================================================================
# kube-tools: Interactive installer & shell configurator for Kubernetes CLI tools
# Tools: fzf, kubectx/kubens, helm, k9s, kubetail, kube-ps1
# ==============================================================================

set -euo pipefail

INSTALL_BIN_DIR="${HOME}/.local/bin"
INSTALL_SHARE_DIR="${HOME}/.local/share/kube-tools"
MARKER_BEGIN="# >>> kube-tools initialize >>>"
MARKER_END="# <<< kube-tools initialize <<<"

DRY_RUN=false
UNINSTALL=false
NON_INTERACTIVE=false

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

usage() {
    cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Options:
  -y, --yes          Non-interactive mode (install all missing tools & default aliases)
  --dry-run          Run interactive wizard or audit without mutating the system
  --uninstall        Remove kube-tools managed binaries, shared repos, and shell aliases (rollback)
  -h, --help         Show this help message
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        -y|--yes|--non-interactive) NON_INTERACTIVE=true; shift ;;
        --dry-run)                  DRY_RUN=true; shift ;;
        --uninstall|--rollback)     UNINSTALL=true; shift ;;
        -h|--help)                  usage; exit 0 ;;
        *) log_error "Opção desconhecida: $1"; usage; exit 1 ;;
    esac
done

run_cmd() {
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Executaria: $*"
    else
        "$@"
    fi
}

# ------------------------------------------------------------------------------
# 1. Environment & Installed Tools Detection
# ------------------------------------------------------------------------------
detect_environment() {
    OS_KERNEL="$(uname -s)"
    ARCH_RAW="$(uname -m)"

    case "$OS_KERNEL" in
        Linux*)  OS="linux" ;;
        Darwin*) OS="darwin" ;;
        *)       log_error "SO não suportado: $OS_KERNEL"; exit 1 ;;
    esac

    case "$ARCH_RAW" in
        x86_64|amd64)   ARCH="amd64"; ARCH_K9S="amd64" ;;
        aarch64|arm64)  ARCH="arm64"; ARCH_K9S="arm64" ;;
        *)              log_error "Arquitetura não suportada: $ARCH_RAW"; exit 1 ;;
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
    export PATH="${INSTALL_BIN_DIR}:${PATH}"
}

# Tool catalog
TOOL_KEYS=("fzf" "kubectx" "helm" "k9s" "kubetail" "kube-ps1")
TOOL_NAMES=(
    "fzf              (Busca interativa fuzzy p/ contextos e namespaces)"
    "kubectx & kubens (Alternância rápida de contexto e namespace)"
    "helm             (Gerenciador de pacotes do Kubernetes)"
    "k9s              (Terminal UI interativo para clusters Kubernetes)"
    "kubetail         (Agregador de logs de múltiplos pods em tempo real)"
    "kube-ps1         (Contexto e namespace atual no prompt do shell)"
)
TOOL_INSTALLED=(0 0 0 0 0 0)
TOOL_LOCATION=("" "" "" "" "" "")
TOOL_SELECTED=(0 0 0 0 0 0)

check_installed_tools() {
    # 0: fzf
    if command -v fzf >/dev/null 2>&1; then
        TOOL_INSTALLED[0]=1
        TOOL_LOCATION[0]="$(command -v fzf)"
    fi

    # 1: kubectx & kubens
    if command -v kubectx >/dev/null 2>&1 && command -v kubens >/dev/null 2>&1; then
        TOOL_INSTALLED[1]=1
        TOOL_LOCATION[1]="$(command -v kubectx)"
    fi

    # 2: helm
    if command -v helm >/dev/null 2>&1; then
        TOOL_INSTALLED[2]=1
        TOOL_LOCATION[2]="$(command -v helm)"
    fi

    # 3: k9s
    if command -v k9s >/dev/null 2>&1; then
        TOOL_INSTALLED[3]=1
        TOOL_LOCATION[3]="$(command -v k9s)"
    fi

    # 4: kubetail
    if command -v kubetail >/dev/null 2>&1; then
        TOOL_INSTALLED[4]=1
        TOOL_LOCATION[4]="$(command -v kubetail)"
    fi

    # 5: kube-ps1
    if [[ -f "${INSTALL_SHARE_DIR}/kube-ps1/kube-ps1.sh" ]]; then
        TOOL_INSTALLED[5]=1
        TOOL_LOCATION[5]="${INSTALL_SHARE_DIR}/kube-ps1/kube-ps1.sh"
    elif [[ -f "/usr/share/kube-ps1/kube-ps1.sh" ]]; then
        TOOL_INSTALLED[5]=1
        TOOL_LOCATION[5]="/usr/share/kube-ps1/kube-ps1.sh"
    fi

    # Pre-select tools that are NOT installed yet
    for i in "${!TOOL_KEYS[@]}"; do
        if [[ "${TOOL_INSTALLED[$i]}" -eq 0 ]]; then
            TOOL_SELECTED[$i]=1
        else
            TOOL_SELECTED[$i]=0
        fi
    done
}

print_diagnostic_report() {
    printf "\n${BOLD}${CYAN}======================================================================${NC}\n"
    printf "${BOLD}${CYAN}  KUBE-TOOLS — Diagnóstico do Ambiente e Ferramentas${NC}\n"
    printf "${BOLD}${CYAN}======================================================================${NC}\n"
    printf "  ${BOLD}Sistema Operacional:${NC} %s (%s)\n" "$OS" "$DISTRO"
    printf "  ${BOLD}Arquitetura:${NC}         %s (%s)\n" "$ARCH" "$ARCH_RAW"
    printf "  ${BOLD}Gerenciador Pacotes:${NC} %s\n" "$PKG_MGR"
    printf "  ${BOLD}Shell Principal:${NC}     %s\n" "$USER_SHELL"
    printf "${CYAN}----------------------------------------------------------------------${NC}\n"
    printf "  ${BOLD}Status atual das ferramentas no sistema:${NC}\n\n"

    for i in "${!TOOL_KEYS[@]}"; do
        local key="${TOOL_KEYS[$i]}"
        if [[ "${TOOL_INSTALLED[$i]}" -eq 1 ]]; then
            printf "   ${GREEN}✔${NC} %-16s ${GREEN}[Já instalado]${NC} ${DIM}(%s)${NC}\n" "$key" "${TOOL_LOCATION[$i]}"
        else
            printf "   ${YELLOW}✗${NC} %-16s ${YELLOW}[Não instalado]${NC}\n" "$key"
        fi
    done
    printf "${CYAN}======================================================================${NC}\n\n"
}

# ------------------------------------------------------------------------------
# 2. Interactive Bash Form (Tools Selection + Aliases Customization)
# ------------------------------------------------------------------------------
interactive_tool_selector() {
    while true; do
        printf "${BOLD}1) Escolha quais ferramentas deseja instalar/atualizar:${NC}\n"
        printf "   ${DIM}(As ferramentas ausentes já vêm pré-selecionadas com [x])${NC}\n\n"

        for i in "${!TOOL_KEYS[@]}"; do
            local num=$((i + 1))
            local mark=" "
            [[ "${TOOL_SELECTED[$i]}" -eq 1 ]] && mark="${GREEN}x${NC}"

            local status_tag=""
            if [[ "${TOOL_INSTALLED[$i]}" -eq 1 ]]; then
                status_tag="${DIM}[instalado]${NC}"
            else
                status_tag="${YELLOW}[ausente]${NC}"
            fi

            printf "   [%b] %d) %s %b\n" "$mark" "$num" "${TOOL_NAMES[$i]}" "$status_tag"
        done

        printf "\n"
        printf "   ${BOLD}Comandos do formulário:${NC}\n"
        printf "   • Digite os números (ex: ${CYAN}1 3 5${NC}) para marcar/desmarcar\n"
        printf "   • Digite ${CYAN}a${NC} para marcar todas | ${CYAN}m${NC} apenas ausentes | ${CYAN}n${NC} nenhuma\n"
        printf "   • Pressione ${GREEN}ENTER${NC} (em branco) para avançar\n\n"

        read -r -p "Sua opção [ENTER p/ confirmar]: " choice || break

        if [[ -z "$choice" ]]; then
            break
        elif [[ "$choice" == "a" || "$choice" == "A" ]]; then
            for i in "${!TOOL_KEYS[@]}"; do TOOL_SELECTED[$i]=1; done
        elif [[ "$choice" == "n" || "$choice" == "N" ]]; then
            for i in "${!TOOL_KEYS[@]}"; do TOOL_SELECTED[$i]=0; done
        elif [[ "$choice" == "m" || "$choice" == "M" ]]; then
            for i in "${!TOOL_KEYS[@]}"; do
                if [[ "${TOOL_INSTALLED[$i]}" -eq 0 ]]; then
                    TOOL_SELECTED[$i]=1
                else
                    TOOL_SELECTED[$i]=0
                fi
            done
        else
            # Parse space/comma separated numbers
            local cleaned="${choice//,/ }"
            for token in $cleaned; do
                if [[ "$token" =~ ^[1-6]$ ]]; then
                    local idx=$((token - 1))
                    if [[ "${TOOL_SELECTED[$idx]}" -eq 1 ]]; then
                        TOOL_SELECTED[$idx]=0
                    else
                        TOOL_SELECTED[$idx]=1
                    fi
                else
                    log_warn "Opção inválida ignorada: $token"
                fi
            done
        fi
        printf "\n"
    done
}

interactive_alias_form() {
    printf "\n${CYAN}----------------------------------------------------------------------${NC}\n"
    printf "${BOLD}2) Configuração de Aliases e Prompt (${USER_SHELL}):${NC}\n\n"

    # kubectx alias
    local input_kctx=""
    read -r -p "   Alias para 'kubectx' [padrão: ${ALIAS_KUBECTX} | '-' p/ desativar]: " input_kctx || true
    if [[ "$input_kctx" == "-" ]]; then
        ALIAS_KUBECTX=""
    elif [[ -n "$input_kctx" ]]; then
        ALIAS_KUBECTX="$input_kctx"
    fi

    # kubens alias
    local input_kns=""
    read -r -p "   Alias para 'kubens'  [padrão: ${ALIAS_KUBENS}  | '-' p/ desativar]: " input_kns || true
    if [[ "$input_kns" == "-" ]]; then
        ALIAS_KUBENS=""
    elif [[ -n "$input_kns" ]]; then
        ALIAS_KUBENS="$input_kns"
    fi

    # Optional alias for kubectl
    local input_k=""
    read -r -p "   Deseja criar alias para 'kubectl'? (ex: k) [ENTER p/ pular]: " input_k || true
    if [[ -n "$input_k" && "$input_k" != "-" ]]; then
        ALIAS_KUBECTL="$input_k"
    fi

    # Optional alias for kubetail
    local input_kt=""
    read -r -p "   Deseja criar alias para 'kubetail'? (ex: kt) [ENTER p/ pular]: " input_kt || true
    if [[ -n "$input_kt" && "$input_kt" != "-" ]]; then
        ALIAS_KUBETAIL="$input_kt"
    fi

    # Custom user aliases loop
    printf "\n   ${DIM}Deseja adicionar outros aliases personalizados? (formato: nome=comando)${NC}\n"
    while true; do
        local custom_alias=""
        read -r -p "   Novo alias [ENTER p/ concluir]: " custom_alias || break
        [[ -z "$custom_alias" ]] && break
        if [[ "$custom_alias" == *"="* ]]; then
            EXTRA_ALIASES+=("$custom_alias")
            log_ok "Alias adicionado: $custom_alias"
        else
            log_warn "Formato inválido. Use nome=comando (ex: kgp=kubectl get pods)"
        fi
    done

    # kube-ps1 prompt toggle
    printf "\n"
    local input_ps1=""
    read -r -p "   Ativar kube-ps1 automaticamente no prompt do shell? [S/n]: " input_ps1 || true
    if [[ "$input_ps1" =~ ^[Nn]$ ]]; then
        ENABLE_KUBE_PS1_PROMPT=false
    else
        ENABLE_KUBE_PS1_PROMPT=true
    fi
}

confirm_summary() {
    printf "\n${BOLD}${CYAN}======================================================================${NC}\n"
    printf "${BOLD}${CYAN}  Resumo da Instalação${NC}\n"
    printf "${BOLD}${CYAN}======================================================================${NC}\n"

    printf "  ${BOLD}Ferramentas selecionadas:${NC}\n"
    local any_tool=false
    for i in "${!TOOL_KEYS[@]}"; do
        if [[ "${TOOL_SELECTED[$i]}" -eq 1 ]]; then
            printf "   • %s\n" "${TOOL_KEYS[$i]}"
            any_tool=true
        fi
    done
    [[ "$any_tool" == "false" ]] && printf "   • ${DIM}(Nenhuma ferramenta será instalada)${NC}\n"

    printf "\n  ${BOLD}Aliases que serão configurados:${NC}\n"
    [[ -n "$ALIAS_KUBECTX" ]]  && printf "   • %s -> kubectx\n" "$ALIAS_KUBECTX"
    [[ -n "$ALIAS_KUBENS" ]]   && printf "   • %s -> kubens\n" "$ALIAS_KUBENS"
    [[ -n "$ALIAS_KUBECTL" ]]  && printf "   • %s -> kubectl\n" "$ALIAS_KUBECTL"
    [[ -n "$ALIAS_KUBETAIL" ]] && printf "   • %s -> kubetail\n" "$ALIAS_KUBETAIL"
    for extra in "${EXTRA_ALIASES[@]}"; do
        local k="${extra%%=*}"
        local v="${extra#*=}"
        printf "   • %s -> %s\n" "$k" "$v"
    done

    printf "\n  ${BOLD}Prompt kube-ps1:${NC} %s\n" "$([[ "$ENABLE_KUBE_PS1_PROMPT" == "true" ]] && echo "Ativado" || echo "Desativado")"
    printf "${CYAN}======================================================================${NC}\n\n"

    local confirm=""
    read -r -p "Confirmar e aplicar configurações? [S/n]: " confirm || true
    if [[ "$confirm" =~ ^[Nn]$ ]]; then
        log_warn "Operação cancelada pelo usuário."
        exit 0
    fi
}

# ------------------------------------------------------------------------------
# 3. Privilege & Package Helpers
# ------------------------------------------------------------------------------
sudo_cmd() {
    if [[ "$(id -u)" -eq 0 ]]; then
        run_cmd "$@"
    elif command -v sudo >/dev/null 2>&1; then
        run_cmd sudo "$@"
    else
        log_error "Permissão de root ou sudo necessária para: $*"
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
            log_info "Instalando dependência base: $dep"
            install_pkg "$dep"
        fi
    done
    run_cmd mkdir -p "$INSTALL_BIN_DIR" "$INSTALL_SHARE_DIR"
}

# ------------------------------------------------------------------------------
# 4. Individual Tool Installers
# ------------------------------------------------------------------------------
install_fzf() {
    log_info "Instalando fzf..."
    if install_pkg fzf; then
        log_ok "fzf instalado via ${PKG_MGR}"
        return 0
    fi

    log_info "Usando fallback via git para fzf..."
    local fzf_dir="${INSTALL_SHARE_DIR}/fzf"
    if [[ -d "$fzf_dir/.git" ]]; then
        run_cmd git -C "$fzf_dir" pull --ff-only
    else
        run_cmd rm -rf "$fzf_dir"
        run_cmd git clone --depth 1 https://github.com/junegunn/fzf.git "$fzf_dir"
    fi
    run_cmd "${fzf_dir}/install" --bin
    run_cmd ln -sf "${fzf_dir}/bin/fzf" "${INSTALL_BIN_DIR}/fzf"
    log_ok "fzf instalado em ${INSTALL_BIN_DIR}/fzf"
}

install_kubectx_kubens() {
    log_info "Instalando kubectx e kubens..."
    local repo_dir="${INSTALL_SHARE_DIR}/kubectx"
    if [[ -d "$repo_dir/.git" ]]; then
        run_cmd git -C "$repo_dir" pull --ff-only
    else
        run_cmd rm -rf "$repo_dir"
        run_cmd git clone --depth 1 https://github.com/ahmetb/kubectx.git "$repo_dir"
    fi
    run_cmd ln -sf "${repo_dir}/kubectx" "${INSTALL_BIN_DIR}/kubectx"
    run_cmd ln -sf "${repo_dir}/kubens" "${INSTALL_BIN_DIR}/kubens"
    log_ok "kubectx e kubens instalados em ${INSTALL_BIN_DIR}"
}

install_helm() {
    log_info "Instalando helm..."
    if [[ "$PKG_MGR" == "brew" || "$PKG_MGR" == "pacman" ]]; then
        if install_pkg helm; then
            log_ok "helm instalado via ${PKG_MGR}"
            return 0
        fi
    fi

    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Instalaria helm via script get-helm-3 em ${INSTALL_BIN_DIR}"
    else
        curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | \
            HELM_INSTALL_DIR="$INSTALL_BIN_DIR" USE_SUDO="false" bash
        log_ok "helm instalado em ${INSTALL_BIN_DIR}/helm"
    fi
}

install_k9s() {
    log_info "Instalando k9s..."
    if [[ "$PKG_MGR" == "brew" || "$PKG_MGR" == "pacman" ]]; then
        if install_pkg k9s; then
            log_ok "k9s instalado via ${PKG_MGR}"
            return 0
        fi
    fi

    local os_title
    [[ "$OS" == "linux" ]] && os_title="Linux" || os_title="Darwin"

    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Baixaria k9s_${os_title}_${ARCH_K9S}.tar.gz em ${INSTALL_BIN_DIR}/k9s"
        return 0
    fi

    local latest_tag
    latest_tag="$(curl -fsSL https://api.github.com/repos/derailed/k9s/releases/latest | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')"
    if [[ -z "$latest_tag" ]]; then
        log_error "Falha ao obter a versão mais recente do k9s no GitHub"
        return 1
    fi

    local tarball_url="https://github.com/derailed/k9s/releases/download/${latest_tag}/k9s_${os_title}_${ARCH_K9S}.tar.gz"
    local tmp_dir
    tmp_dir="$(mktemp -d)"
    curl -fsSL "$tarball_url" -o "${tmp_dir}/k9s.tar.gz"
    tar -xzf "${tmp_dir}/k9s.tar.gz" -C "$tmp_dir" k9s
    install -m 0755 "${tmp_dir}/k9s" "${INSTALL_BIN_DIR}/k9s"
    rm -rf "$tmp_dir"
    log_ok "k9s (${latest_tag}) instalado em ${INSTALL_BIN_DIR}/k9s"
}

install_kubetail() {
    log_info "Instalando kubetail..."
    local repo_dir="${INSTALL_SHARE_DIR}/kubetail"
    if [[ -d "$repo_dir/.git" ]]; then
        run_cmd git -C "$repo_dir" pull --ff-only
    else
        run_cmd rm -rf "$repo_dir"
        run_cmd git clone --depth 1 https://github.com/johanhaleby/kubetail.git "$repo_dir"
    fi
    run_cmd ln -sf "${repo_dir}/kubetail" "${INSTALL_BIN_DIR}/kubetail"
    log_ok "kubetail instalado em ${INSTALL_BIN_DIR}/kubetail"
}

install_kube_ps1() {
    log_info "Instalando kube-ps1..."
    local repo_dir="${INSTALL_SHARE_DIR}/kube-ps1"
    if [[ -d "$repo_dir/.git" ]]; then
        run_cmd git -C "$repo_dir" pull --ff-only
    else
        run_cmd rm -rf "$repo_dir"
        run_cmd git clone --depth 1 https://github.com/jonmosco/kube-ps1.git "$repo_dir"
    fi
    log_ok "kube-ps1 instalado em ${repo_dir}"
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
# 5. Shell RC Configuration (Bash, Zsh, Fish)
# ------------------------------------------------------------------------------
remove_block_from_file() {
    local rc_file="$1"
    [[ -f "$rc_file" ]] || return 0
    if grep -q "$MARKER_BEGIN" "$rc_file"; then
        if [[ "$DRY_RUN" == "true" ]]; then
            log_info "[DRY-RUN] Removeria bloco anterior de $rc_file"
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

build_posix_aliases() {
    local lines=""
    [[ -n "$ALIAS_KUBECTX" ]]  && lines+="alias ${ALIAS_KUBECTX}='kubectx'"$'\n'
    [[ -n "$ALIAS_KUBENS" ]]   && lines+="alias ${ALIAS_KUBENS}='kubens'"$'\n'
    [[ -n "$ALIAS_KUBECTL" ]]  && lines+="alias ${ALIAS_KUBECTL}='kubectl'"$'\n'
    [[ -n "$ALIAS_KUBETAIL" ]] && lines+="alias ${ALIAS_KUBETAIL}='kubetail'"$'\n'
    for extra in "${EXTRA_ALIASES[@]}"; do
        local k="${extra%%=*}"
        local v="${extra#*=}"
        lines+="alias ${k}='${v}'"$'\n'
    done
    printf "%s" "$lines"
}

build_fish_aliases() {
    local lines=""
    [[ -n "$ALIAS_KUBECTX" ]]  && lines+="alias ${ALIAS_KUBECTX} 'kubectx'"$'\n'
    [[ -n "$ALIAS_KUBENS" ]]   && lines+="alias ${ALIAS_KUBENS} 'kubens'"$'\n'
    [[ -n "$ALIAS_KUBECTL" ]]  && lines+="alias ${ALIAS_KUBECTL} 'kubectl'"$'\n'
    [[ -n "$ALIAS_KUBETAIL" ]] && lines+="alias ${ALIAS_KUBETAIL} 'kubetail'"$'\n'
    for extra in "${EXTRA_ALIASES[@]}"; do
        local k="${extra%%=*}"
        local v="${extra#*=}"
        lines+="alias ${k} '${v}'"$'\n'
    done
    printf "%s" "$lines"
}

configure_posix_rc() {
    local rc_file="$1"
    local shell_type="$2"

    remove_block_from_file "$rc_file"

    local prompt_line=""
    if [[ "$ENABLE_KUBE_PS1_PROMPT" == "true" ]]; then
        if [[ "$shell_type" == "bash" ]]; then
            prompt_line='if [[ "$PS1" != *"kube_ps1"* ]]; then PS1="\$(kube_ps1) $PS1"; fi'
        elif [[ "$shell_type" == "zsh" ]]; then
            prompt_line='if [[ "$PROMPT" != *"kube_ps1"* ]]; then PROMPT="\$(kube_ps1) $PROMPT"; fi'
        fi
    fi

    local alias_lines
    alias_lines="$(build_posix_aliases)"

    local block
    block="$(cat <<EOF
${MARKER_BEGIN}
export PATH="\${HOME}/.local/bin:\${PATH}"
${alias_lines}if [ -f "${INSTALL_SHARE_DIR}/kube-ps1/kube-ps1.sh" ]; then
    source "${INSTALL_SHARE_DIR}/kube-ps1/kube-ps1.sh"
    ${prompt_line}
fi
${MARKER_END}
EOF
)"

    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Atualizaria ${rc_file} (${shell_type})"
    else
        touch "$rc_file"
        printf "\n%s\n" "$block" >> "$rc_file"
        log_ok "Configurado ${rc_file} (${shell_type})"
    fi
}

configure_fish_rc() {
    local fish_rc="${HOME}/.config/fish/config.fish"
    remove_block_from_file "$fish_rc"

    local alias_lines
    alias_lines="$(build_fish_aliases)"

    local block
    block="$(cat <<EOF
${MARKER_BEGIN}
fish_add_path -g "\$HOME/.local/bin"
${alias_lines}function __kube_ps1_status
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
        log_info "[DRY-RUN] Atualizaria ${fish_rc} (fish)"
    else
        mkdir -p "$(dirname "$fish_rc")"
        touch "$fish_rc"
        printf "\n%s\n" "$block" >> "$fish_rc"
        log_ok "Configurado ${fish_rc} (fish)"
    fi
}

configure_shells() {
    log_info "Aplicando configurações de shell e aliases..."

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
# 6. Uninstall / Rollback
# ------------------------------------------------------------------------------
uninstall_all() {
    log_info "Revertendo instalação do kube-tools (rollback)..."
    remove_block_from_file "${HOME}/.bashrc"
    remove_block_from_file "${HOME}/.zshrc"
    remove_block_from_file "${HOME}/.config/fish/config.fish"

    for bin in kubectx kubens kubetail k9s helm fzf; do
        if [[ -L "${INSTALL_BIN_DIR}/${bin}" || -f "${INSTALL_BIN_DIR}/${bin}" ]]; then
            run_cmd rm -f "${INSTALL_BIN_DIR}/${bin}"
            log_ok "Removido ${INSTALL_BIN_DIR}/${bin}"
        fi
    done

    if [[ -d "$INSTALL_SHARE_DIR" ]]; then
        run_cmd rm -rf "$INSTALL_SHARE_DIR"
        log_ok "Removido ${INSTALL_SHARE_DIR}"
    fi
    log_ok "Rollback concluído com sucesso."
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
    print_diagnostic_report

    if [[ "$NON_INTERACTIVE" == "false" ]]; then
        interactive_tool_selector
        interactive_alias_form
        confirm_summary
    else
        log_info "Modo não-interativo ativo: instalando ferramentas ausentes com aliases padrão (kctx, kns)."
    fi

    ensure_base_deps
    run_selected_installers
    configure_shells

    printf "\n"
    log_ok "Processo finalizado com sucesso!"
    log_info "Recarregue seu shell para ativar os aliases:"
    case "$USER_SHELL" in
        zsh)  printf "  source ~/.zshrc\n" ;;
        fish) printf "  source ~/.config/fish/config.fish\n" ;;
        *)    printf "  source ~/.bashrc\n" ;;
    esac
}

main "$@"
