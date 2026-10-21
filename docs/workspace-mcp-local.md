# MCP Java Workspace — Execução local com Compose

O serviço `mcp-dev-workspace` é um upstream privado do `central-mcp-gateway`.
Ele roda no Docker na rede do projeto `compose`, **sem publicar porta no host**.
As ferramentas só ficam acessíveis via Gateway depois de allowlist, escopo e
(para escrita/execução) autenticação de proprietário.

## Pré-requisitos

- Java 25 e o JAR gerado pelo repositório `mcp-dev-workspace`, por exemplo:
  `mcp-dev-workspace/target/mcp-dev-workspace-0.1.0-SNAPSHOT.jar`.
- Docker Desktop ativo.
- A imagem do Gateway deve ter o contrato M4-04 ou superior (v0.43.0 no
  primeiro deploy) e a URL deve apontar para
  `http://mcp-dev-workspace:8770/mcp` **dentro do Docker**, nunca para
  `127.0.0.1` do contêiner do Gateway.

Configure somente no `.env` local (não versionar segredos):

```dotenv
MCP_DEV_WORKSPACE_HOST_ROOT=C:/Users/<usuario>/Documents/workspace
MCP_DEV_WORKSPACE_JAR_PATH=C:/Users/<usuario>/Documents/workspace/mcp-dev-workspace/target/mcp-dev-workspace-0.1.0-SNAPSHOT.jar
GATEWAY_WORKSPACE_MCP_BEARER_TOKEN=<token-aleatorio-exclusivo-com-no-minimo-32-bytes>
GATEWAY_UPSTREAM_WORKSPACE_URL=http://mcp-dev-workspace:8770/mcp
```

Não reutilizar `GATEWAY_PUBLIC_BEARER_TOKEN` nem o token interno genérico de
outros serviços. Restringir o `MCP_DEV_WORKSPACE_HOST_ROOT` às pastas desejadas;
a montagem é gravável. A configuração `TRUSTED` autoriza operações dentro
dessa raiz, mas o servidor continua aplicando `PathGuard`, `SecretGuard` e
as restrições de tasks.

## Subir e atualizar

No diretório `personal-platform-infra`:

```powershell
docker compose -f compose/docker-compose.yml --env-file .env --profile workspace config --quiet
docker compose -f compose/docker-compose.yml --env-file .env --profile workspace up -d mcp-dev-workspace
docker compose -f compose/docker-compose.yml --env-file .env --profile gateway up -d --no-deps central-mcp-gateway
```

Se existia um contêiner manual denominado `mcp-dev-workspace`, remova-o
primeiro para evitar que dois servidores recebam o mesmo alias de rede.
Depois de recompilar o JAR, reinicie apenas o serviço Java:

```powershell
docker compose -f compose/docker-compose.yml --env-file .env --profile workspace restart mcp-dev-workspace
```

O perfil `workspace` é **separado** do perfil `gateway`: outras
instalações do Gateway não devem depender de arquivos e tokens locais do
workspace. A política `restart: unless-stopped` mantém o serviço após
reinicializações normais do Docker.

## Validação e segurança

- `docker compose ... --profile workspace ps` deve mostrar o serviço
  ativo; `docker logs compose-mcp-dev-workspace-1` exibe a inicialização
  Java, sem segredos.
- A rede só expõe a porta 8770 aos contêineres do projeto; não há
  `ports:` no serviço.
- `gateway.upstream_capabilities` deve mostrar `workspace: available`.
- `gateway.explain_authorization` distingue `INSUFFICIENT_SCOPE`,
  `OWNER_REQUIRED` e allowlist. Chamadas de leitura podem ser testadas
  com `workspace.list`. Não executar escrita como smoke test.
- Se o ChatGPT estiver conectado por OAuth desde antes de adicionar
  `workspace:read/write/execute`, é necessário reconectar a conta do
  Plugin Gateway MCP para obter um novo token com os escopos permitidos.
- Nunca versionar o `.env`, tokens, resultados de leitura de código-fonte
  privados ou payloads de edição no log de auditoria.

Na imagem Java, o processo roda como UID/GID 10001, com filesystem do
contêiner somente leitura, `/tmp` em tmpfs, capabilities removidas e
`no-new-privileges`. A única superfície gravável persistente é a montagem
do diretório de projetos escolhido.
