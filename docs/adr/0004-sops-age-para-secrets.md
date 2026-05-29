# ADR 0004 — SOPS + age para secrets estruturados

**Data:** 2026-05-29
**Status:** Accepted

## Contexto

O projeto precisa gerenciar secrets (tokens, API keys, kubeconfig) que transitam entre ambientes local e VPS. As alternativas consideradas foram:

| Opção | Prós | Contras |
|---|---|---|
| `.env` só local | simples | não versionável, sem estrutura |
| GitHub Secrets apenas | integrado ao CI | não acessível fora do CI; sem uso local |
| HashiCorp Vault | robusto | operação complexa demais para uso pessoal |
| **SOPS + age** | arquivo versionável, criptografia simples, sem servidor | requer gerenciar a chave age localmente |

## Decisão

Secrets estruturados são armazenados como YAML criptografado via SOPS com backend age:

- `secrets/local.enc.yaml` — secrets do ambiente local
- `secrets/vps.enc.yaml` — secrets do VPS (inclui kubeconfig)
- `.sops.yaml` — registra a chave age pública de cada contexto
- Chaves age privadas ficam em `~/.age/personal-platform.txt` (nunca commitadas)

Para desenvolvimento rápido, `.env` (não commitado) continua sendo o mecanismo principal para Docker Compose. SOPS cobre secrets estruturados e o kubeconfig do VPS para CI.

## Consequências

- **Positivo:** `secrets/*.enc.yaml` podem ser commitados com segurança; histórico auditável
- **Positivo:** sem servidor de secrets para operar; age é simples e sem dependências
- **Negativo:** rotação de secrets exige re-encriptar o arquivo; sem rotação automática
- **Negativo:** perda da chave age privada = perda de acesso aos secrets encriptados; backup da chave é responsabilidade do operador
