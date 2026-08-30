# HARNESS DE VERIFICAÇÃO — Correção de Erros de Conexão

## Mapeamento Segmento → Nível → Ferramenta → Roteiro

| Segmento | Nível | Ferramenta | Status | Roteiro de Experiência |
|----------|-------|-----------|--------|----------------------|
| **00-diagnostico-logs** | 4 (interação UI) | App Flutter + adb logcat | ⚠️ pending | 1. Abrir app no device/emulador. 2. Clicar "Conectar Gmail" → capturar 5s de Logcat. 3. Verificar logs aparecem estruturados com [GMAIL_CONNECT] tags. 4. Repetir para Finanças. 5. Verificar: nenhum token em plaintext nos logs. |
| **01-fix-backend-errors** | 2 (medição API) | curl/httpie + jq | ✅ pronto | 1. Preparar credenciais válidas e inválidas. 2. `POST /auth/connect/gmail -d {...}` → capturar response + timing. 3. Verificar: response < 30s, JSON estruturado com `{ status, error, code }`. 4. Testar com credenciais ruins → error é 401, não 500. 5. Testar com backend offline → error é 503 com retry_after. |
| **02-fix-error-messages** | 4 (interação UI) | App Flutter + simulação de erro backend | ⚠️ pending | 1. Preparar mock backend que retorna erros variados (504, 401, CORS reject). 2. Executar app apontando para mock. 3. Clicar "Conectar Gmail" → mock retorna 504 → app mostra mensagem específica. 4. Capturar screenshot de erro. 5. Repetir com 401, CORS reject. 6. Verificar mensagens são em português, acionáveis (não técnicas). |
| **03-ui-loading-retry** | 4 (interação UI) | App Flutter + video/screenshot time-series | ✅ pronto | 1. Executar app no device/emulador com camera/screen capture ligada. 2. Clicar "Conectar Gmail" → capturar: t=0s (antes), t=100ms (spinner deve aparecer), t=15s (erro aparece). 3. Clicar "Tentar novamente" → capturar spinner aparece novamente (não travado). 4. Simular sucesso → capturar card desaparece suavemente. 5. Verificar: todas as transições < 200ms, sem lag. |
| **04-e2e-test-connections** | 5 (uso prolongado) | App Flutter + contas reais (Google, Pluggy) + screenshots sequência | ⚠️ pending | 1. Preparar device/emulador com app limpo (nenhuma conta conectada). 2. Home screen → "Conectar Gmail" → Google OAuth flow completo → screenshota cada tela. 3. Verificar: token armazenado em Secure Storage (nenhum leak em console). 4. Repetir fluxo para Finanças com Pluggy OAuth. 5. Fechar app, reabrir → verificar contas permanecem (persistência). 6. Settings → logout → verificar cards reaparecem. |

---

## Ferramentas Necessárias

### ✅ Já disponível
- **Flutter SDK** (app já compila e roda)
- **adb** (Android Debug Bridge) — capturar Logcat
- **curl** — testar endpoints HTTP

### ⚠️ Precisa de verificação/setup
1. **Device/Emulador Android conectado via adb**
   - Comando de verificação: `adb devices` deve listar device
   - Status: **Precisa confirmar com usuário**

2. **App Sincro compilável**
   - Comando de teste: `flutter run` deve abrir app no emulador
   - Status: **Precisa confirmar**

3. **Mock backend / ambiente de teste**
   - Para Segmento 02: simular erros sem quebrar produção
   - Opções: 
     - Opção A: Mock simples via curl + arquivo JSON (mais rápido)
     - Opção B: Servidor mock Node.js com `json-server` (mais robusto)
   - Status: **Precisa escolha do usuário**

4. **Contas de teste OAuth**
   - Google account para OAuth (Segmento 04)
   - Pluggy account/API key para Finanças (Segmento 04)
   - Status: **Desconhecido — precisa confirmar**

---

## Comandos de Setup

```bash
# Verificar Flutter e adb
flutter --version
adb devices

# Compilar app para debug (Android)
cd mobile
flutter pub get
flutter run

# Capturar Logcat (em tempo real)
adb logcat | grep -i "GMAIL_CONNECT\|FINANCA"

# Testar endpoint backend
curl -X POST http://localhost:3000/auth/connect/gmail \
  -H "Content-Type: application/json" \
  -d '{"user_id": "test", "code": "abc123"}' \
  -v

# Mock simples: servir JSON estático (Opção A)
python3 -m http.server 8000 --directory ./mock-responses
```

---

## Status de Prontidão

| Componente | Status | Ação |
|-----------|--------|------|
| Flutter + adb | ✅ Presume-se pronto | Confirmar `flutter run` funciona |
| curl | ✅ Pronto | Nenhuma |
| Mock backend | ⚠️ Não existe | Criar (Opção A ou B) antes do Segmento 02 |
| Device/Emulador | ❓ Desconhecido | Confirmar `adb devices` lista device |
| Contas OAuth | ❓ Desconhecido | Confirmar contas Google e Pluggy existem |

---

## Próximos Passos (Antes de BUILD — Fase 3)

✋ **O usuário precisa confirmar:**

1. ✅ Device/Emulador está conectado? (`adb devices` lista device)
2. ✅ App Sincro compila? (`flutter run` abre no emulador)
3. ⚠️ Mock backend: usar **Opção A** (curl) ou **Opção B** (json-server)?
4. ❓ Contas OAuth (Google, Pluggy) existem para Segmento 04?

Assim que confirmar, vou disparar BUILD dos 5 segmentos em paralelo (Ondas 0→1→2).
