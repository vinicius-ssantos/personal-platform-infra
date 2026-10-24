# M4-07 — Private workspace topology / Topologia privada do workspace

## PT-BR — Objetivo e limites

**Somente o Gateway recebe conexões HTTPS do ChatGPT.** O processo Java
`mcp-dev-workspace` escuta na porta 8770 **dentro de uma rede Docker privada**,
sem `ports:`, `network_mode: host` ou túnel público próprio:

```text
ChatGPT → HTTPS (túnel autenticado) → central-mcp-gateway
                                        │
                            workspace-private (internal: true)
                                        │
                                 mcp-dev-workspace:8770/mcp
```

A configuração Compose usa duas redes:
- `default`: Gateway e demais serviços existentes, preservando GitHub,
  Redis, sandbox e proxies já operacionais.
- `workspace-private` com `internal: true`: exclusivamente
  `mcp-dev-workspace` e os Gateways `central-mcp-gateway`, `-blue`
  e `-green`. O Java **não** participa da rede compartilhada e não
  possui saída direta para a Internet. Os três Gateways, por sua vez,
  participam das duas redes.

O Gateway mantém allowlist, escopos `workspace:read/write/execute`,
identidade Owner Mode e token upstream dedicado. A rede privada **não
substitui autenticação** e os guardas Java de caminhos/segredos.

### Primeira ativação ou migração da rede anterior

1. Faça backup do `.env` local fora do repositório. Confirme que
   `GATEWAY_WORKSPACE_MCP_BEARER_TOKEN` tem valor aleatório exclusivo,
   distinto do bearer público e dos outros upstreams.
2. Compile/teste o Java 25 e mantenha o JAR e a montagem do diretório
   com privilégios mínimos. Lembre-se de que a raiz de workspace montada
   é gravável; reduza-a aos repositórios necessários.
3. Renderize e valide a configuração sem imprimir segredos:

```powershell
docker compose -f compose/docker-compose.yml --env-file .env --profile gateway --profile workspace config --quiet
docker compose -f compose/docker-compose.yml --env-file .env --profile gateway --profile workspace config --format json |
  python scripts/verify_workspace_private_topology.py
```

4. A rede nova requer **recriação**, não apenas `docker restart`:
   recrie primeiro o Java e depois os Gateways; preserve os serviços e
   volumes não relacionados.

```powershell
docker compose -f compose/docker-compose.yml --env-file .env --profile workspace up -d --no-deps --force-recreate mcp-dev-workspace
docker compose -f compose/docker-compose.yml --env-file .env --profile gateway up -d --no-deps --force-recreate central-mcp-gateway central-mcp-gateway-blue central-mcp-gateway-green
```

5. Verifique a saúde do Java **a partir do Gateway**, por exemplo
   `http://mcp-dev-workspace:8770/actuator/health/readiness`, e a ferramenta
   somente-leitura `workspace.list` via autorização normal. Nunca exponha
   temporariamente 8770 para testar.

### Testes de segurança e troubleshooting

- `docker ps --format '{{.Names}} {{.Ports}}'`: nenhum contêiner Java deve
  publicar 8770 no host.
- `docker network inspect <projeto>_workspace-private`: somente Java e
  Gateways autorizados aparecem. Não copie objetos `docker inspect` que
  contenham variáveis de ambiente/credenciais para logs.
- `Test-NetConnection 127.0.0.1 -Port 8770` no Windows deve falhar.
  Um scan a partir de fora da máquina também não deve encontrar 8770.
- O Gateway deve alcançar o Java por DNS privado. Outros contêineres
  da rede `default` **não** devem resolvê-lo/alcançá-lo diretamente.
- Consulta ao Gateway retornando `INSUFFICIENT_SCOPE` exige
  reconectar OAuth com escopos explícitos, não abrir a porta Java.
- Erros de `UPSTREAM_AUTH_FAILED` indicam Bearer desalinhado; troque
  o token com rotação coordenada em ambos os serviços.
- Não execute `docker compose config` sem `--quiet` ou sem canalização
  para o validador em logs de CI, pois a saída expandida pode conter
  segredos.

### Rotação e recuperação

1. Coloque o Gateway em manutenção/drain quando possível e suspenda
   operações externas de escrita/execução.
2. Gere um novo Bearer aleatório de pelo menos 32 bytes e guarde-o apenas
   no `.env` local ou sistema de segredos; nunca em comandos versionados.
3. Atualize o mesmo valor no Java e em
   `GATEWAY_WORKSPACE_MCP_BEARER_TOKEN` do Gateway; recrie os serviços.
4. As sessões MCP antigas não passam a representar a nova credencial:
   o Gateway particiona os identificadores pela impressão digital da
   credencial (M4-06). Verifique uma leitura antes de voltar a escrever.
5. Em caso de falha, retire a integração da allowlist/lifecycle e
   recupere a configuração segura. Não faça retry automático de operações
   não idempotentes cujo resultado seja desconhecido.

**Nota:** uma rede `internal: true` impede acesso de saída do Java.
Tarefas Maven/Gradle que precisem baixar dependências deverão usar cache
pré-aquecido ou um proxy de artefatos aprovado na arquitetura. Não
desabilite a rede privada apenas para fazer downloads.

### Gateway em outro host

Não use a URL pública do Java. Configure um overlay autenticado
WireGuard/Tailscale ou serviço privado Cloudflare equivalente, com ACL
autorizando exclusivamente o Gateway, DNS privado e TLS quando o enlace
não for local confiável. Bloqueie 8770 no firewall público, inclusive
IPv6. O endpoint HTTPS público permanece **somente** do Gateway.

---

## EN — Supported secure deployment

The ChatGPT client connects over authenticated HTTPS to **the Gateway only**.
The Java workspace service has no published host port or separate tunnel.
On the same Docker host, it uses an `internal: true` network that contains
only the Java container and the primary/blue/green Gateways. The Gateways
also remain attached to the existing default network for other upstreams.

Run `docker compose ... config --format json | python3
scripts/verify_workspace_private_topology.py` to enforce the topology
without printing expanded environment variables. Validate that port 8770
is unreachable from the host/LAN/public Internet, and that the Gateway
can reach `mcp-dev-workspace:8770/mcp` only on the private network.

For a remote Gateway, use an authenticated private overlay (WireGuard,
Tailscale or equivalent), restrict origin IPs with ACL/firewall policy,
and require TLS across untrusted links. Do not publish the Java service
directly. Rotate the dedicated token on both sides and reinitialize
sessions; never retry an ambiguous write or execute automatically.

Treat the Docker bind-mounted source tree as write-capable. Restrict the
host root, protect OAuth scopes/owner identity, and never emit tokens,
file contents, process output or fully rendered Compose config in CI logs.
