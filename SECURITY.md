# Security Policy & Verification Architecture

`kube-tools` is designed to install Kubernetes CLI tooling safely without compromising workstation integrity.

## 1. Binary & Source Verification (Supply-Chain Hardening & Fail-Closed)

- **Pinned Releases & Pre-Known SHA-256 Checksums**:
  - **`helm`**: Eliminates the execution of unpinned remote scripts (preventing Codecov-style supply chain compromise). Downloads official precompiled binary archives (`helm-vX.Y.Z-<os>-<arch>.tar.gz`) from `https://get.helm.sh/` (fallback to GitHub releases) and validates against pre-known, embedded SHA-256 digests. Directly extracts the `helm` binary into user-space (`~/.local/bin`) without executing arbitrary shell scripts.
  - **`k9s`**: Pinned to a verified stable release with embedded SHA-256 digests per OS/architecture in the script itself, preventing single-origin compromise of binary + checksums.txt.
  - **Zero-Quota GitHub Release Resolution**: Uses HTTP 302 location redirects (`curl -fsSLI`) to resolve releases without consuming unauthenticated GitHub REST API rate limits (avoiding 403 Forbidden on shared CI/corporate networks).
- **Official Upstream Repositories with Tag Pinning**:
  - All Git dependencies (`fzf`, `kubectx`, `kubens`, `kubetail`, `kube-ps1`) are cloned using shallow clones strictly pinned to stable release tags (`--depth 1 --branch <tag>`), preventing unreviewed or malicious commits on the default branch (`main`/`master`) from executing on user workstations.
  - `fzf`: `https://github.com/junegunn/fzf.git` (pinned tag `v0.74.5` or verified OS package manager)
  - `kubectx` / `kubens`: `https://github.com/ahmetb/kubectx.git` (pinned tag `v0.9.5`)
  - `kubetail`: `https://github.com/johanhaleby/kubetail.git` (pinned tag `1.6.22`)
  - `kube-ps1`: `https://github.com/jonmosco/kube-ps1.git` (pinned tag `v1.0.0`)

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
