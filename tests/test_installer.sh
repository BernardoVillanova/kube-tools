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

# Test uninstall / rollback preserves pre-existing tools and only deletes manifest-tracked items
mkdir -p "${SANDBOX_HOME}/.local/bin" "${SANDBOX_HOME}/.local/share/kube-tools"
printf "#!/bin/sh\necho 'pre-existing fzf'\n" > "${SANDBOX_HOME}/.local/bin/fzf"
chmod +x "${SANDBOX_HOME}/.local/bin/fzf"

# Simulate a binary that WAS installed and tracked by kube-tools
printf "#!/bin/sh\necho 'managed kubectx'\n" > "${SANDBOX_HOME}/.local/bin/kubectx"
printf "file:%s/.local/bin/kubectx\n" "$SANDBOX_HOME" > "${SANDBOX_HOME}/.local/share/kube-tools/manifest.state"

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

if [[ ! -f "${SANDBOX_HOME}/.local/bin/kubectx" ]]; then
    printf "  \033[0;32m✔ PASS:\033[0m Manifest-tracked kubectx binary removed by --uninstall\n"
    PASS=$((PASS + 1))
else
    printf "  \033[0;31m✘ FAIL:\033[0m Manifest-tracked kubectx binary was not removed!\n"
    FAIL=$((FAIL + 1))
fi

printf "\n\033[1;32mSummary: %d passed, %d failed\033[0m\n" "$PASS" "$FAIL"
[[ "$FAIL" -eq 0 ]]
