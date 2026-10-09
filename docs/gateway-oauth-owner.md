# Gateway MCP: Owner Mode com OAuth no ambiente local

## Sintoma

`gateway_status` indica Owner Mode habilitado e `allow_dynamic_writes=true`, mas chamadas a `gateway_invoke_discovered_tool` falham com `dynamic writes are disabled` ou `OWNER_REQUIRED`.

## Causa confirmada (v0.41.0)

O status informa o que o servidor **permite ao Owner**, não se a requisição atual é de um Owner. A função `is_owner_request` não eleva sessões OAuth usando `GATEWAY_OWNER_CLIENT_IDS`; elas precisam corresponder a um subject explicitamente confiável definido em `GATEWAY_OWNER_SUBJECTS`. Sem esse vínculo, a autorização utiliza os gates globais (desabilitados por padrão).

O servidor OAuth atual emite subject `oauth:owner` aos clientes autenticados.

## Correção de desenvolvimento (single-user)

No arquivo `.env` local (**não versionar**), adicionar:

```dotenv
GATEWAY_OWNER_SUBJECTS=oauth:owner
GATEWAY_OWNER_MODE_ENABLED=true
GATEWAY_OWNER_ALLOW_DYNAMIC_WRITES=true
```

O `compose/docker-compose.yml` repassa `GATEWAY_OWNER_SUBJECTS` ao contêiner `central-mcp-gateway`. Aplicar com:

```powershell
docker compose --env-file .env -f compose/docker-compose.yml up -d --no-deps central-mcp-gateway
```

Validar `owner_subjects_configured=1` no status e chamar `gateway_explain_authorization` para uma ferramenta de escrita, sem executar uma mutação desnecessária.

## Escopo de repositórios novos

A ferramenta upstream `github.repo_create` também verifica allowlist de criação separada. Para um novo repositório, declarar:

```dotenv
GITHUB_ALLOWED_REPO_CREATIONS=vinicius-ssantos/profilelens
```

Após a criação, incluir o repositório em `GITHUB_ALLOWED_REPOS` (sem usar `*`) para que futuras operações GitHub funcionem, e reiniciar apenas o serviço `github-unified-mcp`:

```powershell
docker compose --env-file .env -f compose/docker-compose.yml up -d --no-deps github-unified-mcp
```

Após concluir a criação, é recomendável limpar `GITHUB_ALLOWED_REPO_CREATIONS` se nenhum novo repositório precisar ser criado.

## Segurança (essencial)

- **Esta configuração somente é apropriada para gateway pessoal, controlado e de desenvolvimento.**
- O servidor OAuth atual usa o mesmo subject `oauth:owner` para todas as sessões OAuth autenticadas; adicioná-lo como Owner eleva todas essas sessões, não só uma instalação do ChatGPT.
- Não usar o mesmo subject genérico em instâncias compartilhadas ou de produção. Para multiusuário, primeiro implementar subjects distintos por usuário e validar a autorização por identidade individual.
- Manter `GATEWAY_ALLOW_DYNAMIC_WRITES` global desativado e as allowlists do GitHub restritas.
- Guardar secrets, hashes, bearer tokens e OAuth client secret exclusivamente no `.env` local/secret manager; jamais versionar ou imprimir valores em logs.
- Verificar a lista de redirect URIs e a proteção da autenticação OAuth antes de habilitar Owner Mode.
- O status do runtime e as políticas de escrita devem ser testados separadamente.

## Evidência de validação

Em 2026-10-09, no Compose local, a requisição `github.repo_create` inicialmente retornou `OWNER_REQUIRED`. Após configurar o subject e reiniciar o serviço, a autorização passou a `allow`; a allowlist específica permitiu criar o repositório privado `vinicius-ssantos/profilelens`.
