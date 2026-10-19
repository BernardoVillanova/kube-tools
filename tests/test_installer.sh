#!/usr/bin/env bash
# ==============================================================================
# kube-tools Automated Verification & Sandbox Test Suite
# ==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
INSTALLER="${SCRIPT_DIR}/install.sh"

PASS=0
FAIL=0

assert_contains() {
    local haystack="$1"
    local needle="$2"
    local test_name="$3"
    if [[ "$haystack" == *"$needle"* ]]; then
        printf "  \033[0;32m✔ PASS:\033[0m %s\n" "$test_name"
        PASS=$((PASS + 1))
    else
        printf "  \033[0;31m✘ FAIL:\033[0m %s (expected '%s')\n" "$test_name" "$needle"
        FAIL=$((FAIL + 1))
    fi
}

assert_file_contains() {
    local file="$1"
    local needle="$2"
    local test_name="$3"
    if [[ -f "$file" ]] && grep -qF "$needle" "$file"; then
        printf "  \033[0;32m✔ PASS:\033[0m %s\n" "$test_name"
        PASS=$((PASS + 1))
    else
        printf "  \033[0;31m✘ FAIL:\033[0m %s (missing '%s' in %s)\n" "$test_name" "$needle" "$file"
        FAIL=$((FAIL + 1))
    fi
}

assert_file_not_contains() {
    local file="$1"
    local needle="$2"
    local test_name="$3"
    if [[ ! -f "$file" ]] || ! grep -qF "$needle" "$file"; then
        printf "  \033[0;32m✔ PASS:\033[0m %s\n" "$test_name"
        PASS=$((PASS + 1))
    else
        printf "  \033[0;31m✘ FAIL:\033[0m %s (unexpected '%s' in %s)\n" "$test_name" "$needle" "$file"
        FAIL=$((FAIL + 1))
    fi
}

printf "\n\033[1;36mRunning kube-tools Verification Suite...\033[0m\n\n"

# 1. Syntax validation
if bash -n "$INSTALLER"; then
    printf "  \033[0;32m✔ PASS:\033[0m Bash syntax check (bash -n install.sh)\n"
    PASS=$((PASS + 1))
else
    printf "  \033[0;31m✘ FAIL:\033[0m Bash syntax check\n"
    FAIL=$((FAIL + 1))
fi

# 2. Version & Help flags
ver_out="$("$INSTALLER" --version)"
assert_contains "$ver_out" "kube-tools v" "CLI --version output"

help_out="$("$INSTALLER" --help)"
assert_contains "$help_out" "--doctor" "CLI --help lists --doctor"
assert_contains "$help_out" "--uninstall" "CLI --help lists --uninstall"

# 3. Doctor mode in English & Portuguese
doc_en="$("$INSTALLER" --doctor --lang en)"
assert_contains "$doc_en" "Environment & Toolchain Audit" "Doctor mode in English (--lang en)"
assert_contains "$doc_en" "SHA-256 verification engine available" "Doctor verifies SHA-256 engine"

doc_pt="$("$INSTALLER" --doctor --lang pt)"
assert_contains "$doc_pt" "Diagnóstico do Ambiente e Ferramentas" "Doctor mode in Portuguese (--lang pt)"

# 4. Sandboxed Interactive Form, Custom Aliases, Idempotency & Rollback
SANDBOX_HOME="$(mktemp -d)"
trap 'rm -rf "$SANDBOX_HOME"' EXIT

mkdir -p "${SANDBOX_HOME}/.config/fish"
touch "${SANDBOX_HOME}/.bashrc" "${SANDBOX_HOME}/.zshrc" "${SANDBOX_HOME}/.config/fish/config.fish"

# Simulate interactive user:
# - 'n' (select no tools to download so test runs offline & without root)
# - '' (confirm tool selection)
# - 'mykctx' (custom kubectx alias)
# - 'mykns' (custom kubens alias)
# - 'k' (kubectl alias)
# - 'kt' (kubetail alias)
# - 'kgp=kubectl get pods' (custom extra alias)
# - '' (finish extra aliases)
# - 'Y' (enable kube-ps1)
# - 'Y' (confirm summary)
printf "n\n\nmykctx\nmykns\nk\nkt\nkgp=kubectl get pods\n\nY\nY\n" | \
    HOME="$SANDBOX_HOME" SHELL="/bin/bash" "$INSTALLER" --lang en >/dev/null

assert_file_contains "${SANDBOX_HOME}/.bashrc" "alias mykctx='kubectx'" "Custom kubectx alias written to .bashrc"
assert_file_contains "${SANDBOX_HOME}/.bashrc" "alias mykns='kubens'" "Custom kubens alias written to .bashrc"
assert_file_contains "${SANDBOX_HOME}/.bashrc" "alias k='kubectl'" "Optional kubectl alias written to .bashrc"
assert_file_contains "${SANDBOX_HOME}/.bashrc" "alias kt='kubetail'" "Optional kubetail alias written to .bashrc"
assert_file_contains "${SANDBOX_HOME}/.bashrc" "alias kgp='kubectl get pods'" "Extra custom alias written to .bashrc"
assert_file_contains "${SANDBOX_HOME}/.zshrc" "alias mykctx='kubectx'" "Custom kubectx alias written to .zshrc"
assert_file_contains "${SANDBOX_HOME}/.config/fish/config.fish" "alias mykctx 'kubectx'" "Custom kubectx alias written to config.fish"

# Test idempotency (running a second time replaces previous block instead of duplicating)
printf "n\n\nkctx\nkns\n\n\n\nY\nY\n" | \
    HOME="$SANDBOX_HOME" SHELL="/bin/bash" "$INSTALLER" --lang en >/dev/null

marker_count="$(grep -c "# >>> kube-tools initialize >>>" "${SANDBOX_HOME}/.bashrc")"
assert_contains "$marker_count" "1" "Idempotent RC block update (single block in .bashrc)"
assert_file_not_contains "${SANDBOX_HOME}/.bashrc" "mykctx" "Old custom alias cleanly replaced on re-run"
assert_file_contains "${SANDBOX_HOME}/.bashrc" "alias kctx='kubectx'" "New default alias present after re-run"

# 5. Security Regression Tests: Alias Injection, Quote Escaping, Symlink Preservation & Path Confinement
# Make .bashrc a symlink to a dotfiles directory (like GNU Stow / Chezmoi)
mkdir -p "${SANDBOX_HOME}/dotfiles"
mv "${SANDBOX_HOME}/.bashrc" "${SANDBOX_HOME}/dotfiles/bashrc"
ln -s "${SANDBOX_HOME}/dotfiles/bashrc" "${SANDBOX_HOME}/.bashrc"

# Attempt to inject a malicious alias name ('bad;echo_pwned') and a valid alias with single quotes
printf "n\n\nbad;echo_pwned\nkns\n\n\nevil;id=whoami\nkjson=kubectl get pods -o jsonpath='{.items}'\n\nY\nY\n" | \
    HOME="$SANDBOX_HOME" SHELL="/bin/bash" "$INSTALLER" --lang en >/dev/null

assert_file_not_contains "${SANDBOX_HOME}/.bashrc" "bad;echo_pwned" "Rejects command injection in kubectx alias name"
assert_file_not_contains "${SANDBOX_HOME}/.bashrc" "evil;id" "Rejects command injection in custom alias name"
assert_file_contains "${SANDBOX_HOME}/.bashrc" "alias kjson='kubectl get pods -o jsonpath='\\''{.items}'\\'''" "Escapes single quotes safely in POSIX alias value"
assert_file_contains "${SANDBOX_HOME}/.config/fish/config.fish" "alias kjson 'kubectl get pods -o jsonpath=\\'{.items}\\''" "Escapes single quotes safely in Fish alias value"

if [[ -L "${SANDBOX_HOME}/.bashrc" ]]; then
    printf "  \033[0;32m✔ PASS:\033[0m Preserves .bashrc symlink (Stow/Chezmoi dotfiles compatibility)\n"
    PASS=$((PASS + 1))
else
    printf "  \033[0;31m✘ FAIL:\033[0m .bashrc symlink was clobbered!\n"
    FAIL=$((FAIL + 1))
fi

# 6. Test uninstall / rollback preserves pre-existing tools and blocks manifest path traversal
mkdir -p "${SANDBOX_HOME}/.local/bin" "${SANDBOX_HOME}/.local/share/kube-tools"
printf "#!/bin/sh\necho 'pre-existing fzf'\n" > "${SANDBOX_HOME}/.local/bin/fzf"
chmod +x "${SANDBOX_HOME}/.local/bin/fzf"
printf "sensitive data\n" > "${SANDBOX_HOME}/outside_secret.txt"

# Simulate a binary that WAS installed and tracked by kube-tools + malicious manifest entries
printf "#!/bin/sh\necho 'managed kubectx'\n" > "${SANDBOX_HOME}/.local/bin/kubectx"
cat <<EOF > "${SANDBOX_HOME}/.local/share/kube-tools/manifest.state"
file:${SANDBOX_HOME}/.local/bin/kubectx
file:${SANDBOX_HOME}/.local/bin/../../outside_secret.txt
dir:${SANDBOX_HOME}
dir:/
pkg:apt:openssh-server
EOF

HOME="$SANDBOX_HOME" SHELL="/bin/bash" "$INSTALLER" --uninstall --lang en >/dev/null
assert_file_not_contains "${SANDBOX_HOME}/.bashrc" "kube-tools initialize" "Rollback removes block from .bashrc"
assert_file_not_contains "${SANDBOX_HOME}/.zshrc" "kube-tools initialize" "Rollback removes block from .zshrc"
assert_file_not_contains "${SANDBOX_HOME}/.config/fish/config.fish" "kube-tools initialize" "Rollback removes block from config.fish"

if [[ -f "${SANDBOX_HOME}/.local/bin/fzf" ]]; then
    printf "  \033[0;32m✔ PASS:\033[0m Pre-existing fzf binary preserved after --uninstall\n"
    PASS=$((PASS + 1))
else
    printf "  \033[0;31m✘ FAIL:\033[0m Pre-existing fzf binary was deleted by --uninstall!\n"
    FAIL=$((FAIL + 1))
fi

if [[ -f "${SANDBOX_HOME}/outside_secret.txt" ]]; then
    printf "  \033[0;32m✔ PASS:\033[0m Manifest path-confinement blocked '../../outside_secret.txt' deletion\n"
    PASS=$((PASS + 1))
else
    printf "  \033[0;31m✘ FAIL:\033[0m Manifest path traversal deleted file outside .local/bin!\n"
    FAIL=$((FAIL + 1))
fi

if [[ ! -f "${SANDBOX_HOME}/.local/bin/kubectx" ]]; then
    printf "  \033[0;32m✔ PASS:\033[0m Manifest-tracked kubectx binary removed by --uninstall\n"
    PASS=$((PASS + 1))
else
    printf "  \033[0;31m✘ FAIL:\033[0m Manifest-tracked kubectx binary was not removed!\n"
    FAIL=$((FAIL + 1))
fi

# 7. Supply Chain Security Regression Tests
# 7.1. Helm must not execute get-helm-3 remote script
assert_file_not_contains "$INSTALLER" "get-helm-3" "Helm installer does not download/execute get-helm-3 remote script"

# 7.2. Git clones must be pinned to tags/branches
# shellcheck disable=SC2016
assert_file_contains "$INSTALLER" 'git clone --depth 1 --branch "$FZF_PINNED_TAG"' "fzf git clone pinned to release tag"
# shellcheck disable=SC2016
assert_file_contains "$INSTALLER" 'git clone --depth 1 --branch "$KUBECTX_PINNED_TAG"' "kubectx git clone pinned to release tag"
# shellcheck disable=SC2016
assert_file_contains "$INSTALLER" 'git clone --depth 1 --branch "$KUBETAIL_PINNED_TAG"' "kubetail git clone pinned to release tag"
# shellcheck disable=SC2016
assert_file_contains "$INSTALLER" 'git clone --depth 1 --branch "$KUBE_PS1_PINNED_TAG"' "kube-ps1 git clone pinned to release tag"

# 7.3. Embedded SHA-256 Checksums must be declared
assert_file_contains "$INSTALLER" "get_pinned_helm_sha256" "Helm embedded SHA-256 integrity lookup present"
assert_file_contains "$INSTALLER" "get_pinned_k9s_sha256" "k9s embedded SHA-256 integrity lookup present"

# 7.4. GitHub REST API rate-limit avoidance
assert_file_not_contains "$INSTALLER" "api.github.com/rate_limit" "Network check does not consume GitHub API rate limits"
assert_file_contains "$INSTALLER" "get_github_latest_release_tag" "Direct HTTP 302 redirect tag resolver declared"

printf "\n\033[1;32mSummary: %d passed, %d failed\033[0m\n" "$PASS" "$FAIL"
[[ "$FAIL" -eq 0 ]]
