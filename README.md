# kube-tools

[![CI](https://github.com/BernardoVillanova/kube-tools/actions/workflows/ci.yml/badge.svg)](https://github.com/BernardoVillanova/kube-tools/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](./LICENSE)
[![Shell: Bash/Zsh/Fish](https://img.shields.io/badge/Shell-Bash%20%7C%20Zsh%20%7C%20Fish-4EAA25)](./install.sh)
[![Platform: Linux & macOS](https://img.shields.io/badge/Platform-Linux%20%7C%20macOS-informational)](./install.sh)

> 🌐 **Language / Idioma:** **English** (current) | **[Português (Brasil)](./README.pt-BR.md)**

**`kube-tools`** is a centralized, single-script interactive installer and shell configurator for the essential Kubernetes CLI ecosystem (`fzf`, `kubectx`, `kubens`, `helm`, `k9s`, `kubetail`, and `kube-ps1`).

It automatically audits your environment, detects your Operating System, CPU architecture, package manager, and active shell (`bash`, `zsh`, `fish`), verifies binary integrity via **SHA-256 checksums**, and configures custom shell aliases (`kctx`, `kns`, and user-defined shortcuts) idempotently.

---

## Why `kube-tools`?

Setting up a new workstation or DevOps jumpbox usually requires visiting 6+ repositories, looking up release tarballs for your architecture, and manually editing `.bashrc`, `.zshrc`, or `config.fish`.

`kube-tools` centralizes the entire workflow into a single, auditable script ([`install.sh`](./install.sh)) backed by automated tests, SHA-256 verification, a read-only `--doctor` diagnostic mode, and instant `--uninstall` rollback:

```
┌──────────────────────────────────────────────────────────────────────────┐
│                        ./install.sh Execution Flow                       │
├──────────────────────────────────────────────────────────────────────────┤
│  1. Pre-Flight Audit   -> Detects OS, Arch, Pkg Manager, Shell & Versions│
│  2. Interactive Form   -> Toggle tools to install + customize aliases    │
│  3. Verified Download  -> Package Mgr / Upstream Git / SHA-256 Tarballs  │
│  4. Idempotent Config  -> Updates ~/.bashrc, ~/.zshrc, config.fish       │
└──────────────────────────────────────────────────────────────────────────┘
```

---

## Included Toolchain

| Tool | Upstream | Description | Verification Method |
| :--- | :--- | :--- | :--- |
| **[fzf](https://github.com/junegunn/fzf)** | `junegunn/fzf` | Interactive fuzzy finder for `kubectx` & `kubens` | System Package Mgr / Pinned Release Tag (`v0.74.5`) |
| **[kubectx & kubens](https://github.com/ahmetb/kubectx)** | `ahmetb/kubectx` | Fast switching between Kubernetes contexts and namespaces | Pinned Release Tag (`v0.9.5`) |
| **[helm](https://helm.sh/)** | `helm/helm` | The Kubernetes Package Manager | Official precompiled binary + Embedded SHA-256 (`v3.22.1`) |
| **[k9s](https://k9scli.io/)** | `derailed/k9s` | Terminal UI to observe and manage Kubernetes clusters | Pinned Release (`v0.51.0`) + Embedded SHA-256 + Zero-Quota Redirect |
| **[kubetail](https://github.com/johanhaleby/kubetail)** | `johanhaleby/kubetail` | Aggregate logs from multiple pods simultaneously | Pinned Release Tag (`1.6.22`) |
| **[kube-ps1](https://github.com/jonmosco/kube-ps1)** | `jonmosco/kube-ps1` | Display current K8s context & namespace on shell prompt | Pinned Release Tag (`v1.0.0`) |

---

## Interactive Wizard (4-Step Bash Form)

When you run `./install.sh`, an interactive terminal wizard guides you through:

1. **Environment & Installed Tools Audit**:
   - Inspects your OS, architecture (`amd64`/`arm64`), package manager, `kubectl` client version, and checks which tools are **already installed** (`✔ [Installed]`) vs **missing** (`✗ [Not installed]`), pre-selecting only the missing ones.
2. **Tool Selection Checklist**:
   - Toggle individual tools (`1`–`6`), select all (`a`), select missing only (`m`), or select none (`n`).
3. **Alias & Prompt Customization**:
   - Keep default aliases (`kctx` -> `kubectx`, `kns` -> `kubens`), customize them to any name, or disable them (`-`).
   - Optionally define aliases for `kubectl` (e.g., `k`), `kubetail` (e.g., `kt`), and add unlimited custom aliases in `name=command` format (e.g., `kgp=kubectl get pods`).
   - Choose whether to enable `kube-ps1` in your shell prompt automatically.
4. **Confirmation Summary**:
   - Review all selected tools and aliases before any change is applied to disk.

---

## Quick Start

### 1. Clone & Run Interactive Installer

```bash
git clone https://github.com/BernardoVillanova/kube-tools.git
cd kube-tools
chmod +x install.sh
./install.sh
```

### 2. Direct One-Liner (Non-Interactive / Default Aliases)

```bash
curl -fsSL https://raw.githubusercontent.com/BernardoVillanova/kube-tools/main/install.sh | bash -s -- --yes
```

---

## CLI Options & Verifications

```bash
# Run read-only health, PATH, SHA-256 engine, and connectivity diagnostics
./install.sh --doctor

# Preview the wizard or installation without modifying the system
./install.sh --dry-run

# Force English or Portuguese interface explicitly
./install.sh --lang en
./install.sh --lang pt

# Non-interactive mode (installs all missing tools + kctx/kns aliases)
./install.sh --yes

# Complete rollback (removes managed binaries, repos, and shell RC blocks)
./install.sh --uninstall
```

---

## Repository Structure & Quality Assurance

This repository includes automated verification scripts and CI pipelines so you can audit and test the installer before running it on production workstations:

```text
kube-tools/
├── .github/workflows/ci.yml   # GitHub Actions CI (ShellCheck + sandboxed test suite)
├── tests/test_installer.sh    # Automated sandbox tests (dry-run, doctor, aliases, rollback)
├── install.sh                 # Centralized single-file installer & shell configurator
├── Makefile                   # Developer & operator shortcuts (make doctor, make test)
├── SECURITY.md                # Security model, SHA-256 verification & immutability notes
├── LICENSE                    # MIT License
├── README.md                  # English documentation (default)
└── README.pt-BR.md            # Portuguese documentation
```

### Running the Test Suite Locally

All tests run inside an isolated temporary `$HOME` directory and never touch your real user configuration:

```bash
make test
```

---

## Supported Environments

- **Operating Systems:** Linux (Debian/Ubuntu `apt`, Arch/CachyOS `pacman`, Fedora/RHEL `dnf`/`yum`, openSUSE `zypper`, Alpine `apk`) and macOS (`brew`).
- **Architectures:** `x86_64` (`amd64`) and `aarch64` (`arm64`).
- **Shells:** `bash` (`~/.bashrc`), `zsh` (`~/.zshrc`), and `fish` (`~/.config/fish/config.fish`).

---

## License

Released under the [MIT License](./LICENSE).
