# ADR 0011 — Ansible para bootstrap de máquinas

**Data:** 2026-05-29
**Status:** Accepted

## Contexto

O projeto precisa provisionar duas máquinas de forma reproduzível: WSL2 local e VPS Ubuntu. As alternativas consideradas foram scripts shell puros, Terraform (provider `local` / SSH), e Ansible.

| Opção | Idempotência | Multi-máquina | Curva |
|---|---|---|---|
| Scripts shell | manual | manual | baixa |
| Terraform | sim | sim | média |
| **Ansible** | sim (módulos) | sim (inventory) | média |

Terraform é adequado para infraestrutura de nuvem (recursos Cloudflare, VMs), não para configuração de SO dentro de máquinas existentes. Shell scripts funcionam mas não são idempotentes nativamente.

## Decisão

Usar Ansible para bootstrap de máquinas com inventários separados:

- `ansible/inventory/local.ini` — WSL2 local (`ansible_connection=local`)
- `ansible/inventory/vps.ini` — VPS via SSH

Playbooks:
- `bootstrap-wsl.yml` — ambiente completo WSL2 (ferramentas + diretórios)
- `bootstrap-vps.yml` — VPS (k3s + ferramentas + ufw)
- `install-tools.yml` — instalação isolada de ferramentas (sem bootstrap completo)

## Consequências

- **Positivo:** idempotente: rodar o playbook múltiplas vezes não quebra o estado
- **Positivo:** `creates:` nos módulos shell evita reinstalações desnecessárias
- **Negativo:** Ansible não vem pré-instalado; requer `pip install ansible` antes do primeiro bootstrap (bootstrap do bootstrap)
- **Negativo:** módulos `community.general` (ex. `ufw`) requerem `ansible-galaxy collection install community.general`
