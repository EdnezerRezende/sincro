# Segmento 01 — Corrigir Erros de Backend (Timeout/Auth/CORS)

## Identificação
- **ID:** 01-fix-backend-errors
- **Onda:** 1 (depende de diagnóstico)
- **Depende de:** 00-diagnostico-logs
- **Critério:** score >= 90 E impressed == true

## Entregável
- Backend endpoints `/auth/connect/gmail` e `/auth/connect/pluggy` (ou similar) funcionam sem erro
- Timeout aumentado para valor razoável (30s mínimo para auth externo)
- CORS configurado corretamente (se erro for CORS)
- Respostas de erro incluem `{ status: int, error: string, code: string }` estruturado

**Arquivos afetados (backend):**
- `server/routes/auth.js` (ou equivalente)
- `server/config/cors.js`
- `server/services/oauth.js` (ou equivalente)

## Critérios de aceitação
1. **Endpoint responde sem timeout:** POST /auth/connect/gmail retorna em < 30s (sucesso ou erro claro)
2. **CORS funcionando:** Request do app mobile não é bloqueado por CORS
3. **Erro estruturado:** Se falha, retorna { status: 40x/50x, error: "descricao clara", code: "TIMEOUT|AUTH_FAILED|PROVIDER_DOWN" }
4. **Fallback/retry:** Se provider (Google/Pluggy) está down, endpoint retorna 503 com retry_after, não 500 ambíguo

## Benchmark
APIs de produção (Google, Pluggy) respondem dentro de 30s ou retornam erro estruturado com código específico. Backend Sincro deve fazer o mesmo.

## Método de verificação (preenchido na Fase 2)
- Fazer POST /auth/connect/gmail via curl/Postman com credenciais válidas
- Verificar: resposta em < 30s, erro é estruturado (não erro genérico 500)
- Repetir com credenciais inválidas → verifica se erro diferencia "auth failed" de "timeout"
- Verificar CORS headers na resposta (Access-Control-Allow-Origin)
