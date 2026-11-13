# M4 — Pré-flight seguro do Gateway blue/green

**Estado (13/11/2026):** diagnóstico somente leitura. Este documento não autoriza promoção, troca de tráfego, alteração de OAuth ou uso de repositórios reais como fixtures.

## Por que existe

A release `v0.48.0` já foi publicada, mas a implantação observada ainda é **blue ativo v0.46.3** e **green reserva v0.45.0**. O arquivo `.env` local ainda seleciona essas imagens. Além disso, em 10/11 o `compose/docker-compose.yml` local tinha alterações não commitadas ligadas a outra atividade de infraestrutura. Executar o controlador antigo sem essa inspeção pode não implantar a imagem pretendida ou aplicar mudanças alheias.

## Diagnóstico sem efeitos colaterais

Após revisão do PR, rode no PowerShell 5.1+ a partir da raiz do repositório:

```powershell
.\scripts\gateway-bluegreen-preflight.ps1 -Target green -CandidateTag v0.48.0 -ExpectedActive blue
```

Também é possível executar o script de uma cópia isolada apontando `-InfraRoot` para a instalação atual. Ele verifica:
- existência de `.env` sem exibir seu conteúdo;
- slot ativo registrado em `%LOCALAPPDATA%\personal-platform\gateway-slot.json`;
- `/readyz` dos dois slots via `127.0.0.1:8041/8042`, exigindo versões e status `ready`;
- imagens atualmente selecionadas por `docker compose config --format json` em memória, sem imprimi-las com environment/segredos;
- ausência de diferenças locais em `compose/docker-compose.yml` e `scripts/gateway-bluegreen-promote.ps1`;
- resolução da imagem candidata por variável **apenas no processo** `CENTRAL_MCP_GATEWAY_GREEN_IMAGE`, com restauração imediata do valor anterior;
- garantia de que a configuração candidata não muda o slot atualmente ativo.

Retornos: `PREFLIGHT=PASS_READ_ONLY` com exit 0; `PREFLIGHT=BLOCKED` com código diagnóstico e exit 2. **Passar não autoriza promoção automática.** A versão candidata precisa existir no GHCR e passar CI, verificação de segurança e revisão de configuração separadamente. O pré-flight não realiza download da imagem.

### Resultado esperado com a instalação observada em 10/11

Com o arquivo Compose modificado localmente, o resultado esperado é `REASON=DEPLOYMENT_CONFIG_HAS_UNREVIEWED_LOCAL_CHANGES`. Não apague nem reverta as mudanças do outro trabalho para satisfazer o pré-flight; revise-as e use um fluxo de integração próprio.

## Hibernação esperada do blue (não é necessariamente falha)

A tarefa agendada `MCP Core Wake Proxy` utiliza
`scripts/mcp-wake-proxy.py`. O valor padrão de
`MCP_WAKE_PROXY_IDLE_SECONDS` é **900 segundos (15 minutos)**.
Após esse período sem requisições MCP/OAuth ativas, o controlador executa
`docker compose stop` no último slot utilizado e nos serviços de apoio.
O arquivo de estado permanece selecionando `blue`, pois ele representa
a **rota desejada**, não o estado de execução do container.

Assim, `Exited (0)` sem OOM pode indicar **hibernação intencional**,
e não crash. Em 13/11/2026, observou-se um intervalo de aproximadamente
15 minutos entre iniciar e parar o blue, com a tarefa agendada ativa.
Uma requisição MCP/OAuth pública válida passando pelo wake proxy reativa
o slot selecionado. Consultar diretamente `/readyz` na porta 8041
**não** realiza esse despertar.

Essa regra **não dispensa o preflight**: se o blue estiver hibernando,
a verificação somente leitura retorna `GATEWAY_BLUE_NOT_READY`. A
aceitação de implantação deve ocorrer em janela acordada e controlada,
com autorização operacional. Não reinicie automaticamente, não troque a
rota e não trate o slot adormecido como saudável. Antes de afirmar que
houve crash, confira o ciclo de vida do Docker, a tarefa agendada e
o caminho da requisição. O green pode permanecer saudável durante a
hibernação do blue.

O CI possui testes sem Docker para o timeout de 900 segundos, proteção de
requisições em andamento, seleção do slot e contabilidade de wake/release.
Esses testes não atestam a disponibilidade do endpoint real nem aprovam
uma implantação.

## Verificação opcional do digest do manifesto remoto

Use `-ExpectedManifestDigest` com o SHA-256 previamente revisado do **índice OCI** para conferir o manifesto remoto da imagem candidata por `docker buildx imagetools inspect`, sem baixar suas camadas. A validação reprova digest incorreto, ausente ou resposta inválida. Sem o parâmetro, retorna `CANDIDATE_MANIFEST_CHECK=NOT_REQUESTED`; quando confere, retorna `CANDIDATE_MANIFEST_CHECK=VERIFIED`.

```powershell
.\scripts\gateway-bluegreen-preflight.ps1 -Target green -CandidateTag v0.48.0 -ExpectedActive blue `
  -ExpectedManifestDigest sha256:833bd971971bc0024a2b41859c9f4e7d229f3ad6698d049eb262702edad2eacb
```

O digest acima foi observado para v0.48.0 em 13/11/2026. Confirme-o novamente antes de implantar. A verificação não atesta assinatura, proveniência do build nem impede a mudança posterior de uma tag. A implantação deve utilizar digest fixado após revisão independente; o pré-flight não altera a configuração. O bloqueio por Compose modificado ocorre antes de qualquer consulta ao registro.

## Promoção (etapa independente, sujeita a revisão)

Após o pré-flight passar e após autorização explícita:
1. Registrar versão, digest da imagem, backup da configuração e slot anterior. Não mostrar tokens em logs, screenshots ou issues.
2. Definir **de forma controlada e persistente** a imagem do slot **inativo green** com o digest revisado da v0.48.0. O pré-flight apenas simula essa interpolação; não altera `.env`.
3. Executar o controlador existente `gateway-bluegreen-promote.ps1 -Target green` **somente** após revisão das alterações e da imagem, mantendo blue v0.46.3 disponível. O controlador atual inicia green, espera ready e atualiza o arquivo local de seleção de rota. Não executá-lo só por este documento.
4. Confirmar version/readyz, 16 ferramentas `workspace.*` congeladas, `confirmation_token` opcional nos dois schemas estáticos, OAuth/refresh saudável e ausência de regressões read-only. Documentar auditoria/correlação sem divulgar payloads sensíveis.
5. Se houver falha, devolver a seleção para blue apenas por procedimento aprovado e validar `readyz`; não reiniciar nem remover a versão anterior sem inspeção.

**Aprovação ChatGPT é outra etapa:** o catálogo congelado pelo ChatGPT não se atualiza com a promoção. Um administrador/operador autorizado precisa usar o refresh da página do plugin, iniciar conversa nova e conferir os schemas. Não contornar aprovação humana `central-mcp-gateway#415` nem usar `gateway.invoke_discovered_tool` para writes.

## Aceite / evidências

- [ ] Pré-flight passa em repositório com Compose revisado (sem mudanças conflitantes)
- [ ] Digest/tag v0.48.0 confirmado de forma independente
- [ ] Publicação da imagem e testes CI registrados
- [ ] Green promovido de maneira controlada, blue preservado
- [ ] Catálogo realmente observado no ChatGPT atualizado por operador autorizado
- [ ] Teste de escrita em fixture TRUSTED descartável e consentimento independente
- [ ] M4 #84/#85/#87 só fechadas após os respectivos gates

Referências: [Docker Compose — precedência de variáveis](https://docs.docker.com/compose/how-tos/environment-variables/envvars-precedence/), [Docker Compose up](https://docs.docker.com/reference/cli/docker/compose/up), [OpenAI — MCP personalizado](https://help.openai.com/en/articles/12584461-connecting-custom-mcp-servers-in-chatgpt).
