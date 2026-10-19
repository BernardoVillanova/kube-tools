# Security Policy & Verification Architecture

`kube-tools` is designed to install Kubernetes CLI tooling safely without compromising workstation integrity.

## 1. Binary & Source Verification (Fail-Closed)

- **SHA-256 Checksum Validation**:
  - **`k9s`**: Enforces HTTPS TLS 1.2+ (`--proto '=https' --tlsv1.2`), validates the release tag against strict semver (`^v[0-9]+\.[0-9]+\.[0-9]+`), downloads the official `checksums.txt` from `derailed/k9s` GitHub releases, and verifies the 64-character SHA-256 digest (`sha256sum`, `shasum -a 256`, or `openssl dgst -sha256`) before extracting. Verification is **fail-closed**: if `checksums.txt` is missing, malformed, or mismatches, installation aborts immediately and temporary files are purged.
  - **`helm`**: Downloads the official Helm installer over TLS 1.2+ into an isolated `0700` temporary directory (`umask 077`), verifies non-empty payload, and executes with `VERIFY_CHECKSUM="true"` and `USE_SUDO="false"`, installing into user-space (`~/.local/bin`).
- **Official Upstream Repositories Only**:
  - `fzf`: `https://github.com/junegunn/fzf.git` (or verified OS package manager)
  - `kubectx` / `kubens`: `https://github.com/ahmetb/kubectx.git`
  - `kubetail`: `https://github.com/johanhaleby/kubetail.git`
  - `kube-ps1`: `https://github.com/jonmosco/kube-ps1.git`

## 2. Shell RC Injection Protection & Symlink Preservation

- **Strict Alias Identifier Validation**: All user-supplied alias names (`kubectx`, `kubens`, `kubectl`, `kubetail`, and custom `name=command` aliases) are validated against `^[a-zA-Z_][a-zA-Z0-9_-]*$`. Metacharacters (`;`, `|`, `&`, spaces) are rejected before touching any shell configuration file.
- **Safe Single-Quote Escaping**: Custom alias commands containing single quotes (such as `kubectl get pods -o jsonpath='{...}'`) are escaped specifically for POSIX (`' -> '\''`) and Fish (`' -> \'`) to prevent shell syntax breakage or command injection.
- **Dotfiles Symlink Preservation**: Updates to `~/.bashrc`, `~/.zshrc`, and `~/.config/fish/config.fish` use `mktemp` with `umask 077` and write in-place (`cat "$tmp_file" > "$rc_file"`) rather than `mv`, preserving symlinks managed by GNU Stow, Chezmoi, or Yadm.

## 3. Manifest-Scoped Rollback & Path Confinement

- **Pre-Existing Tool Protection**: `kube-tools` records installed artifacts in `~/.local/share/kube-tools/manifest.state` **only** if the tool was not already installed prior to execution.
- **Path Traversal Confinement**: During `./install.sh --uninstall`, `is_safe_managed_path` verifies that every `file:` entry is strictly inside `~/.local/bin/` and every `dir:` entry is strictly inside `~/.local/share/kube-tools/`, blocking `..` traversal or root/home directory deletion even if `manifest.state` is tampered with.
- **Package Whitelisting**: `pkg:` entries in `manifest.state` are restricted to `^(apt|pacman|dnf|yum|zypper|apk|brew):(fzf|helm|k9s)$`.

## 4. Pre-Flight Auditing

Before running any installation, users can inspect their system and simulate every command in read-only mode:

```bash
./install.sh --doctor
./install.sh --dry-run
```
