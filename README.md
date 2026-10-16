# kube-tools

Automatização interativa para auditoria, instalação e configuração de ferramentas essenciais de Kubernetes no terminal, com detecção automática de Sistema Operacional, arquitetura, gerenciador de pacotes e shell (`bash`, `zsh`, `fish`).

## Fluxo do Formulário Interativo

Ao executar `./install.sh`, o script guia você por 4 etapas:

1. **Diagnóstico e Verificação Inicial**:
   - Identifica SO, distribuição, arquitetura (`amd64`/`arm64`), gerenciador de pacotes e shell ativo.
   - Verifica quais ferramentas **já estão instaladas** (`✔ [Já instalado]`) e quais estão **ausentes** (`✗ [Não instalado]`), pré-selecionando apenas as que faltam.
2. **Seleção de Ferramentas (Checklist Interativo)**:
   - Permite marcar ou desmarcar individualmente quais ferramentas deseja instalar ou atualizar (`1` a `6`, `a` para todas, `m` apenas ausentes, `n` nenhuma).
3. **Personalização de Aliases e Prompt**:
   - Permite manter os aliases padrão (`kctx` para `kubectx` e `kns` para `kubens`), alterá-los para outro nome ou desativá-los.
   - Permite criar aliases opcionais para `kubectl` (ex: `k`), `kubetail` (ex: `kt`) e adicionar quantos aliases extras desejar no formato `nome=comando` (ex: `kgp=kubectl get pods`).
   - Permite escolher se deseja ativar o `kube-ps1` automaticamente no prompt.
4. **Resumo e Confirmação**:
   - Exibe tudo o que será feito antes de aplicar qualquer alteração no sistema.

## Ferramentas Disponíveis

- **[fzf](https://github.com/junegunn/fzf)** — Busca interativa fuzzy para seleção rápida de contextos e namespaces.
- **[kubectx & kubens](https://github.com/ahmetb/kubectx)** — Alternância rápida entre contextos (`kubectx`) e namespaces (`kubens`).
- **[helm](https://helm.sh/)** — Gerenciador de pacotes para Kubernetes.
- **[k9s](https://k9scli.io/)** — Terminal UI interativo para observabilidade e gerenciamento de clusters.
- **[kubetail](https://github.com/johanhaleby/kubetail)** — Agregador de logs de múltiplos pods simultaneamente.
- **[kube-ps1](https://github.com/jonmosco/kube-ps1)** — Exibição do contexto e namespace atual do Kubernetes diretamente no prompt do shell.

## Como Usar

### Modo Interativo (Formulário)

```bash
chmod +x install.sh
./install.sh
```

### Pré-verificação (Dry-Run)

Audite o formulário ou o modo automático sem alterar o sistema:

```bash
./install.sh --dry-run
```

### Modo Automático (Sem perguntas / CI)

Instala todas as ferramentas ausentes e configura `kctx` e `kns` automaticamente:

```bash
./install.sh --yes
```

### Rollback / Desinstalação

Para reverter todas as alterações nos arquivos de configuração do shell e remover os binários gerenciados em `~/.local/bin` e `~/.local/share/kube-tools`:

```bash
./install.sh --uninstall
```
