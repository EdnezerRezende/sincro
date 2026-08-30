# Segmento 05 — Componente Modal (Confirmação/Alert)

- **Onda**: 0
- **Depende de**: 00-design-system
- **Escopo de arquivos**: `mobile/lib/core/widgets/app_dialog.dart` ou similar

## Entregável
Modal/Dialog reutilizável com:
- Título, conteúdo, actions (botões)
- Fundo semi-transparente (scrim)
- Animação de entrada suave (fade/scale)
- Suporta 1–2 ações (dismiss, confirm, destructive)
- Botões com estados claros (primário, secundário, destruidor)
- Acessível via teclado (ESC fecha, TAB navega, ENTER confirma)

## Critérios de aceitação
1. Fundo scrim é semi-transparente (70% preto aprox) e clica para fechar
2. Modal tem sombra e está centralizado
3. Título é claro e legível
4. Conteúdo não ocupa mais de 60% da tela (scrollável se necessário)
5. Botões estão claros: primário (cor), secundário (outline), destrutivo (vermelho)
6. Animação é suave (200–300ms) e não jittery
7. Teclado: ESC fecha, TAB navega, ENTER clica botão focado
8. Dark mode: modal e botões ainda legíveis

## Benchmark
Material Design 3 AlertDialog ou iOS UIAlertController. Simples, claro, profissional.

## Método de verificação
- Nível: 2 (interactive)
- Ferramenta: App emulador, teste de gestos e teclado (se suportado)

### Roteiro de experiência
1. Abrir tela que dispara modal (ex: deletar contato, desconectar Gmail)
2. Modal aparece → é centralizado? Scrim é escuro?
3. Clicar fora modal (scrim) → fecha?
4. Observar botões → primário é claro? Destrutivo é vermelho?
5. Clicar botão primário → modal fecha e ação ocorre?
6. Abrir modal novamente, observar animação → é suave?
7. Testar dark mode → cores ainda visíveis?

## Histórico de notas
| Rodada | Nota | Status |
|---|---|---|
| 1 | — | pending |
