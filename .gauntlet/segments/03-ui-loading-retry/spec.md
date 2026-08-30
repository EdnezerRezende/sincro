# Segmento 03 — UI/UX: Loading, Retry, Estados Visuais

## Identificação
- **ID:** 03-ui-loading-retry
- **Onda:** 2 (depende de erros serem corrigíveis)
- **Depende de:** 01-fix-backend-errors, 02-fix-error-messages
- **Critério:** score >= 90 E impressed == true

## Entregável
- Botão "Conectar Gmail" muda para estado loading durante tentativa (spinner ou disabled com "Conectando...")
- Se falha, botão volta ao estado normal, modal/snackbar mostra erro específico
- Botão "Tentar novamente" está sempre disponível (não recarrega página inteira)
- Estados visuais: normal → loading → success (desaparece card) OU error (habilita retry)

**Arquivos afetados (frontend):**
- `lib/features/inbox/presentation/widgets/` (widget de card de conexão)
- `lib/features/finances/presentation/widgets/` (widget de card de conexão)
- Estados gerenciados via Provider/Riverpod/GetX

## Critérios de aceitação
1. **Loading state visível:** Botão desabilitado, spinner aparece, texto muda para "Conectando..."
2. **Erro sem full reload:** Ao falhar, apenas modal/snackbar muda, usuário pode retry imediatamente
3. **Retry sempre funciona:** Clicar "Tentar novamente" n vezes deve fazer nova tentativa cada vez (não fica travado)
4. **Sucesso é claro:** Ao conectar, card desaparece ou muda para "✓ Conectado" antes de desaparecer
5. **UX fluido:** Transições suaves, sem lag ou atraso visual (< 200ms de resposta visual)

## Benchmark
Apps reais (Nubank, Spotify) mostram: toque → spinner aparece → erro em modal com botão retry, ou sucesso com transição.

## Método de verificação (preenchido na Fase 2)
- Executar app no emulador/device
- Clicar "Conectar Gmail" → spinner aparece em < 200ms
- Esperar timeout simulado → modal de erro aparece com "Tentar novamente"
- Clicar "Tentar novamente" → spinner aparece novamente (não travado)
- Desabilitar provider de erro backend → conectar com sucesso → verificar se card desaparece suavemente
- Repetir para Finanças
