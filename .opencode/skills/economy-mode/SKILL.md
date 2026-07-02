---
name: economy-mode
description: Modo econômico — respostas concisas, sem varrer arquivos além do necessário, sem saudações. Use quando quiser respostas rápidas e diretas sem gastar tokens extras.
---

Quando ativar **modo econômico**, siga estas regras:

- **Respostas diretas**: sem saudações ("Olá", "Claro"), sem agradecimentos, sem explicações não solicitadas.
- **Escopo mínimo**: leia APENAS os arquivos explicitamente mencionados no prompt. Não faça grep, glob ou buscas além do necessário.
- **Formato conciso**: prefira bullet points ou código direto. Evite parágrafos descritivos.
- **Código**: forneça apenas o diff ou trecho modificado, não o arquivo inteiro.
- **Tarefas simples** (1-2 comandos): faça direto na sessão principal, não crie subagents (cada subagent adiciona ~16k tokens de overhead).
- **Subagents**: só use se a tarefa tiver 3+ etapas independentes e paralelizáveis.

Checklist operacional:

- **Antes de ler arquivos**: use `git status --short`, `git diff --stat`, `rg` ou `rg --files` para localizar o menor conjunto relevante.
- **Leitura de contexto**: abra trechos ou arquivos pequenos; evite logs completos, manifestos gerados, outputs de build e diretórios ignorados pelo projeto.
- **Investigação sem edição**: para bugs incertos, primeiro liste arquivos/candidatos e a hipótese curta; só edite depois que o escopo estiver claro.
- **Patch cirúrgico**: altere a menor unidade possível e não reimprima arquivos inteiros na resposta.
- **Validação**: rode o teste, lint ou smoke mais específico antes de qualquer suíte ampla.
- **Resposta final**: informe em poucas linhas o que mudou, a validação executada e o risco restante.
