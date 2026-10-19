# kube-tools (Português)

[![CI](https://github.com/BernardoVillanova/kube-tools/actions/workflows/ci.yml/badge.svg)](https://github.com/BernardoVillanova/kube-tools/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](./LICENSE)
[![Shell: Bash/Zsh/Fish](https://img.shields.io/badge/Shell-Bash%20%7C%20Zsh%20%7C%20Fish-4EAA25)](./install.sh)
[![Platform: Linux & macOS](https://img.shields.io/badge/Platform-Linux%20%7C%20macOS-informational)](./install.sh)

> 🌐 **Language / Idioma:** **[English](./README.md)** | **Português (Brasil)** (atual)

O **`kube-tools`** é um instalador interativo centralizado em um único script e configurador de shell para o ecossistema essencial de ferramentas CLI do Kubernetes (`fzf`, `kubectx`, `kubens`, `helm`, `k9s`, `kubetail` e `kube-ps1`).

Ele audita automaticamente o seu ambiente, detecta Sistema Operacional, arquitetura de CPU, gerenciador de pacotes e shell ativo (`bash`, `zsh`, `fish`), valida a integridade de binários via **checksums SHA-256** e configura aliases personalizados (`kctx`, `kns` e atalhos extras definidos pelo usuário) de forma idempotente.

---

## Por que usar o `kube-tools`?

Configurar uma nova máquina de trabalho ou bastion DevOps geralmente exige visitar mais de 6 repositórios diferentes, buscar binários específicos para a sua arquitetura e editar manualmente `.bashrc`, `.zshrc` ou `config.fish`.

O `kube-tools` centraliza todo esse processo em um único script auditável ([`install.sh`](./install.sh)), acompanhado de testes automatizados, verificação SHA-256, modo de diagnóstico somente-leitura (`--doctor`) e rollback instantâneo (`--uninstall`):

```
┌──────────────────────────────────────────────────────────────────────────┐
│                     Fluxo de Execução do ./install.sh                    │
├──────────────────────────────────────────────────────────────────────────┤
│  1. Auditoria Inicial  -> Detecta SO, Arch, Pkg Mgr, Shell e Versões     │
│  2. Formulário Bash    -> Seleção de ferramentas + customização aliases  │
│  3. Download Verificado-> Gerenciador / Git Oficial / Tarball c/ SHA-256 │
│  4. Config Idempotente -> Atualiza ~/.bashrc, ~/.zshrc e config.fish     │
└──────────────────────────────────────────────────────────────────────────┘
```

---

## Ferramentas Incluídas

| Ferramenta | Repositório Oficial | Descrição | Método de Verificação |
| :--- | :--- | :--- | :--- |
| **[fzf](https://github.com/junegunn/fzf)** | `junegunn/fzf` | Busca interativa fuzzy para `kubectx` e `kubens` | Gerenciador de Pacotes / Tag Fixada Estável (`v0.74.5`) |
| **[kubectx & kubens](https://github.com/ahmetb/kubectx)** | `ahmetb/kubectx` | Alternância rápida entre contextos e namespaces K8s | Tag Fixada Estável (`v0.9.5`) |
| **[helm](https://helm.sh/)** | `helm/helm` | Gerenciador de pacotes para Kubernetes | Binário oficial pré-compilado + SHA-256 embutido (`v3.22.1`) |
| **[k9s](https://k9scli.io/)** | `derailed/k9s` | Terminal UI para observabilidade e gestão de clusters | Release Fixada (`v0.51.0`) + SHA-256 embutido + Redirect sem cota API |
| **[kubetail](https://github.com/johanhaleby/kubetail)** | `johanhaleby/kubetail` | Agregador de logs de múltiplos pods simultaneamente | Tag Fixada Estável (`1.6.22`) |
| **[kube-ps1](https://github.com/jonmosco/kube-ps1)** | `jonmosco/kube-ps1` | Exibe contexto e namespace atual no prompt do shell | Tag Fixada Estável (`v1.0.0`) |

---

## Formulário Interativo (4 Etapas no Terminal)

Ao executar `./install.sh`, um formulário interativo guia você por:

1. **Diagnóstico e Verificação Inicial**:
   - Identifica SO, distribuição, arquitetura (`amd64`/`arm64`), gerenciador de pacotes, versão do `kubectl` e verifica quais ferramentas **já estão instaladas** (`✔ [Já instalado]` + versão/caminho) e quais estão **ausentes** (`✗ [Não instalado]`), pré-selecionando apenas as que faltam.
2. **Seleção de Ferramentas (Checklist Interativo)**:
   - Permite marcar ou desmarcar individualmente quais ferramentas deseja instalar ou atualizar (`1` a `6`, `a` para todas, `m` apenas ausentes, `n` nenhuma).
3. **Personalização de Aliases e Prompt**:
   - Permite manter os aliases padrão (`kctx` para `kubectx` e `kns` para `kubens`), alterá-los para outro nome ou desativá-los (`-`).
   - Permite criar aliases opcionais para `kubectl` (ex.: `k`), `kubetail` (ex.: `kt`) e adicionar quantos aliases extras desejar no formato `nome=comando` (ex.: `kgp=kubectl get pods`).
   - Permite escolher se deseja ativar o `kube-ps1` automaticamente no prompt.
4. **Resumo e Confirmação**:
   - Exibe tudo o que será feito antes de aplicar qualquer alteração no sistema.

---

## Como Usar

### 1. Clonar e Executar o Formulário Interativo

```bash
git clone https://github.com/BernardoVillanova/kube-tools.git
cd kube-tools
chmod +x install.sh
./install.sh
```

### 2. Instalação Direta em Uma Linha (Modo Não-Interativo)

```bash
curl -fsSL https://raw.githubusercontent.com/BernardoVillanova/kube-tools/main/install.sh | bash -s -- --yes
```

---

## Opções de Linha de Comando e Verificações

```bash
# Executar diagnóstico completo de saúde, PATH, SHA-256 e conectividade (somente leitura)
./install.sh --doctor

# Simular o formulário ou a instalação sem modificar o sistema
./install.sh --dry-run

# Forçar idioma da interface (Inglês ou Português)
./install.sh --lang pt
./install.sh --lang en

# Modo automático sem perguntas (instala ausentes + aliases padrão kctx/kns)
./install.sh --yes

# Rollback / Desinstalação completa (remove binários, repositórios e blocos do shell)
./install.sh --uninstall
```

---

## Estrutura do Repositório e Garantia de Qualidade

Para garantir máxima confiabilidade e transparência, o repositório conta com suíte de testes isolada em sandbox, validação de segurança e pipeline de CI:

```text
kube-tools/
├── .github/workflows/ci.yml   # Pipeline GitHub Actions (ShellCheck + testes em sandbox)
├── tests/test_installer.sh    # Suíte de testes automatizados (dry-run, doctor, aliases, rollback)
├── install.sh                 # Script centralizado de instalação e configuração de shell
├── Makefile                   # Atalhos para diagnóstico, testes e instalação
├── SECURITY.md                # Política de segurança e verificação de integridade SHA-256
├── LICENSE                    # Licença MIT
├── README.md                  # Documentação padrão em Inglês
└── README.pt-BR.md            # Documentação em Português (Brasil)
```

### Executando os Testes Localmente

Todos os testes rodam em um diretório `$HOME` temporário isolado e nunca alteram os arquivos reais do seu usuário:

```bash
make test
```

---

## Ambientes Suportados

- **Sistemas Operacionais:** Linux (Debian/Ubuntu `apt`, Arch/CachyOS `pacman`, Fedora/RHEL `dnf`/`yum`, openSUSE `zypper`, Alpine `apk`) e macOS (`brew`).
- **Arquiteturas:** `x86_64` (`amd64`) e `aarch64` (`arm64`).
- **Shells:** `bash` (`~/.bashrc`), `zsh` (`~/.zshrc`) e `fish` (`~/.config/fish/config.fish`).

---

## Licença

Distribuído sob a [Licença MIT](./LICENSE).
