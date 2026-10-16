# Security Policy & Verification Architecture

`kube-tools` is designed to install Kubernetes CLI tooling safely without compromising workstation integrity.

## 1. Binary & Source Verification

- **SHA-256 Checksum Validation**:
  - **`k9s`**: Downloads the official `checksums.txt` from `derailed/k9s` GitHub releases and verifies the SHA-256 digest of the platform tarball (`sha256sum`, `shasum -a 256`, or `openssl dgst -sha256`) before extracting. If the checksum mismatches, installation aborts immediately.
  - **`helm`**: Executes the official Helm installer with `VERIFY_CHECKSUM="true"` and `USE_SUDO="false"`, installing into user-space (`~/.local/bin`).
- **Official Upstream Repositories Only**:
  - `fzf`: `https://github.com/junegunn/fzf.git` (or verified OS package manager)
  - `kubectx` / `kubens`: `https://github.com/ahmetb/kubectx.git`
  - `kubetail`: `https://github.com/johanhaleby/kubetail.git`
  - `kube-ps1`: `https://github.com/jonmosco/kube-ps1.git`

## 2. User-Space Isolation & Least Privilege

- All standalone binaries and symlinks are installed in `~/.local/bin` and `~/.local/share/kube-tools`.
- `sudo` is **only** invoked if you choose to install packages via the system package manager (`apt`, `pacman`, `dnf`, `yum`, `zypper`, `apk`).

## 3. Idempotent Shell Configuration & Clean Rollback

- Shell RC files (`~/.bashrc`, `~/.zshrc`, `~/.config/fish/config.fish`) are modified strictly inside bounded markers:
  ```text
  # >>> kube-tools initialize >>>
  ...
  # <<< kube-tools initialize <<<
  ```
- Running `./install.sh --uninstall` removes the marker block cleanly without touching any other user configuration.

## 4. Pre-Flight Auditing

Before running any installation, users can inspect their system and simulate every command in read-only mode:

```bash
./install.sh --doctor
./install.sh --dry-run
```
