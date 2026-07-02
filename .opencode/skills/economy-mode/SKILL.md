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
