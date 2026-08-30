# Segmento 04 — Teste End-to-End: Conexões Funcionais

## Identificação
- **ID:** 04-e2e-test-connections
- **Onda:** 2 (paralelo com 03, após 01 estar pronto)
- **Depende de:** 01-fix-backend-errors, 02-fix-error-messages
- **Critério:** score >= 90 E impressed == true

## Entregável
- Teste manual end-to-end: clicar "Conectar Gmail" → autenticação Google → app recebe token → card desaparece
- Teste manual end-to-end: clicar "Conectar conta" (Finanças) → autenticação Pluggy → app recebe token → card desaparece
- Verificação: token armazenado em Secure Storage, não exposido em logs
- Verificação: após reconexão do app, contas permanecem conectadas (persistência)

**Artefatos:**
- Relatório de testes com screenshots de cada etapa
- Checklist: [✓] Gmail conecta, [✓] Finanças conecta, [✓] Tokens salvos, [✓] Logout remove tokens, etc.

## Critérios de aceitação
1. **Gmail conecta com sucesso:** Fluxo completo sem erros, card desaparece ou mostra "Conectado"
2. **Finanças conecta com sucesso:** Idem Gmail
3. **Tokens persistem:** Fechar e reabrir app, contas continuam conectadas
4. **Logout funciona:** Se feature existe, desconectar remove token de Secure Storage
5. **Nenhuma exposição de token:** Logs, screenshots, console não mostram tokens reais

## Benchmark
Um app de produção precisa de jornada completa testada: autenticação → armazenamento → persistência → logout. Sem isso, "conecta" é mentira.

## Método de verificação (preenchido na Fase 2)
- Setup: Sincro em device/emulador, contas Google e Pluggy válidas disponíveis
- Teste 1: Home screen → "Conectar Gmail" → OAuth flow Google → sucesso → card desaparece
- Teste 2: Home screen → "Conectar conta" → OAuth flow Pluggy → sucesso → card desaparece
- Teste 3: Fechar app completamente → reabrir → verificar contas permanecem conectadas
- Teste 4: Settings → desconectar Gmail → verificar card reaparece na Home
- Verificar: Console/Logcat não mostra tokens em plaintext
