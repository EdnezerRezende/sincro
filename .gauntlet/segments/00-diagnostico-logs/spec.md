# Segmento 00 — Diagnóstico e Logging Detalhado

## Identificação
- **ID:** 00-diagnostico-logs
- **Onda:** 0 (fundação)
- **Depende de:** nenhum
- **Critério:** score >= 90 E impressed == true

## Entregável
- Logging detalhado no fluxo OAuth/API para Gmail e Finanças
- Captura: provider, timestamp, HTTP status, request/response headers (sem tokens)
- Console mostra: [GMAIL_CONNECT] Iniciando... → [GMAIL_CONNECT] Timeout em 15s → [GMAIL_CONNECT] HTTP 504
- Logs persistem em Logcat (Android) e podem ser exportados para debug

**Arquivos afetados:**
- `lib/features/*/services/auth_service.dart` (ou similar)
- `lib/core/services/api_client.dart`

## Critérios de aceitação
1. **Erro específico identificado:** Executar conexão Gmail/Finanças e verificar console/Logcat mostra motivo exato (timeout, 401, 403, CORS, etc.)
2. **Logs estruturados:** Cada tentativa de conexão gera entrada com timestamp, provider, status, duration
3. **Sem exposição de sensível:** Token/credenciais nunca aparecem nos logs (substituir por `***`)
4. **Rastreabilidade:** Erro na tela ("Não foi possível...") correlaciona com log (ID de transação ou timestamp)

## Benchmark
Apps reais (Nubank, Google) mostram no console exatamente qual API falhou, HTTP status, latência. Aqui, desenvolvedor consegue ler log e saber: foi timeout? Credencial ruim? API do servidor indisponível?

## Método de verificação (preenchido na Fase 2)
- Executar app no emulador/device
- Clicar "Conectar Gmail" → capturar console/Logcat
- Clicar "Conectar conta" (Finanças) → capturar console/Logcat
- Verificar: logs aparecem estruturados, erros específicos visíveis, nenhum token exposto
