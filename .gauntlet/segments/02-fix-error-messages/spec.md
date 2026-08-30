# Segmento 02 — Mensagens de Erro Específicas

## Identificação
- **ID:** 02-fix-error-messages
- **Onda:** 1 (paralelo com 01)
- **Depende de:** 00-diagnostico-logs
- **Critério:** score >= 90 E impressed == true

## Entregável
- Remover mensagem genérica "Não foi possível conectar..."
- Substituir por erros específicos ao usuário:
  - "Timeout ao conectar com Google. Verifique sua conexão."
  - "Google negou acesso. Tente novamente com outra conta."
  - "Servidor indisponível. Tente em alguns minutos."
  - "Sua conta não tem permissão. Contate suporte."

**Arquivos afetados (frontend):**
- `lib/features/inbox/screens/` ou `lib/features/*/presentation/` (onde erro é exibido)
- `lib/core/services/api_client.dart` (mapping de erro HTTP → mensagem)
- `lib/core/i18n/pt-br.json` (se usar i18n)

## Critérios de aceitação
1. **Sem "Não foi possível":** Mensagem nunca é genérica; traduz HTTP 504→"Timeout", 401→"Acesso negado"
2. **Acionável:** Mensagem sugere ação (tente novamente, verifique conexão, contate suporte)
3. **Idioma:** Mensagens em português claro, sem jargão técnico
4. **Consistência:** Gmail e Finanças usam mesmo padrão de mensagem (não duplicar lógica)

## Benchmark
Aplicativos reais mostram: "Spotify está com problemas. Verifique sua conexão ou tente mais tarde." Nunca "Erro desconhecido".

## Método de verificação (preenchido na Fase 2)
- Executar app
- Simular erro no backend: desativar endpoint Gmail, ou forçar timeout
- Verificar mensagem exibida é específica (não genérica)
- Repetir para Finanças
- Verificar se mensagem é compreensível para usuário leigo
