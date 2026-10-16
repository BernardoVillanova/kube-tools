# kube-tools

Automatização para instalação e configuração de ferramentas essenciais de Kubernetes no terminal, com detecção automática de Sistema Operacional, arquitetura, gerenciador de pacotes e shell (`bash`, `zsh`, `fish`).

## Ferramentas Instaladas

- **[fzf](https://github.com/junegunn/fzf)** — Busca interativa fuzzy para seleção rápida de contextos e namespaces.
- **[kubectx & kubens](https://github.com/ahmetb/kubectx)** — Alternância rápida entre contextos (`kubectx`) e namespaces (`kubens`).
- **[helm](https://helm.sh/)** — Gerenciador de pacotes para Kubernetes.
- **[k9s](https://k9scli.io/)** — Terminal UI interativo para observabilidade e gerenciamento de clusters.
- **[kubetail](https://github.com/johanhaleby/kubetail)** — Agregador de logs de múltiplos pods simultaneamente.
- **[kube-ps1](https://github.com/jonmosco/kube-ps1)** — Exibição do contexto e namespace atual do Kubernetes diretamente no prompt do shell.

## Aliases Configurados Automaticamente

O script identifica o seu shell ativo (`~/.bashrc`, `~/.zshrc` ou `~/.config/fish/config.fish`) e adiciona automaticamente:

| Alias | Comando Original | Descrição |
| :--- | :--- | :--- |
| `kctx` | `kubectx` | Alterna entre contextos do Kubernetes (interativo com `fzf`) |
| `kns` | `kubens` | Alterna entre namespaces do Kubernetes (interativo com `fzf`) |

## Sistemas e Ambientes Suportados

- **Sistemas Operacionais:** Linux (Debian/Ubuntu `apt`, Arch `pacman`, Fedora/RHEL `dnf`/`yum`, openSUSE `zypper`, Alpine `apk`) e macOS (`brew`).
- **Arquiteturas:** `x86_64` (`amd64`) e `aarch64` (`arm64`).
- **Shells:** `bash`, `zsh` e `fish`.

## Como Usar

### 1. Pré-verificação (Dry-Run)

Audite o que será detectado e configurado sem alterar o sistema:

```bash
chmod +x install.sh
./install.sh --dry-run
```

### 2. Instalação

Execute o instalador:

```bash
./install.sh
```

Após concluir, recarregue o seu shell:

```bash
# Bash
source ~/.bashrc

# Zsh
source ~/.zshrc

# Fish
source ~/.config/fish/config.fish
```

### 3. Rollback / Desinstalação

Para reverter todas as alterações nos arquivos de configuração do shell e remover os binários gerenciados em `~/.local/bin` e `~/.local/share/kube-tools`:

```bash
./install.sh --uninstall
```
