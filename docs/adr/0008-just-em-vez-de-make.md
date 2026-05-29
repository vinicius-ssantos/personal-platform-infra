# ADR 0008 — `just` em vez de Makefile

**Data:** 2026-05-29
**Status:** Accepted

## Contexto

O projeto roda em Windows 11 (PowerShell) + WSL2 (Bash). `make` tem comportamento inconsistente no Windows: requer instalação separada (chocolatey/winget), trata tabs de forma sensível, e suas receitas assumem shell POSIX. Alternativas consideradas: `make`, `npm scripts`, `task` (taskfile.dev), `just`.

## Decisão

Usar `just` como task runner com suporte explícito a PowerShell:

```just
set windows-shell := ["powershell.exe", "-NoLogo", "-Command"]
```

Scripts de smoke que requerem PowerShell (`.ps1`) são chamados diretamente das receitas. Scripts Bash (`.sh`) são chamados com `bash` explícito para funcionar tanto no WSL2 quanto no CI (Linux).

## Consequências

- **Positivo:** um único `Justfile` funciona em Windows (PowerShell) e Linux/WSL2 (Bash) sem condicionais
- **Positivo:** sintaxe mais simples que Makefile; sem armadilhas de tab vs espaço
- **Positivo:** `just --list` documenta os comandos disponíveis automaticamente
- **Negativo:** `just` não vem pré-instalado; requer instalação manual (coberta pelo bootstrap Ansible)
- **Negativo:** sem suporte nativo a dependências entre receitas com detecção de mudança de arquivos (ao contrário de `make`)
