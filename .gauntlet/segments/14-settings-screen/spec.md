# Segmento 14 — Settings Screen

- **Onda**: 2
- **Depende de**: 06-appbar, 08-scaffold-layout, 01-component-button
- **Escopo de arquivos**: `mobile/lib/features/settings/settings_screen.dart`

## Entregável
Settings screen redesenhada com:
- Seções (conta, notificações, privacidade, sobre)
- Toggles para configurações booleanas (notifications on/off)
- Dropdowns para seleção múltipla
- Botões para ações (logout, apagar conta, feedback)
- Informações versão do app
- Sem overload visual

## Critérios de aceitação
1. Seções têm headings claros (Account, Notifications, Privacy, About)
2. Toggles são visíveis e respondem ao toque (on/off claro)
3. Dropdowns têm label claro e valor selecionado visível
4. Botões destrutivos (logout, delete) são vermelhos e pedem confirmação
5. Versão do app é legível em rodapé
6. Espaçamento é consistente (padding, gaps)
7. Dark mode funciona
8. Scroll necessário é suave (não jarring)
9. Ações pedem confirmação onde apropriado (logout, delete)
10. Nenhuma ação é irreversível sem warning

## Benchmark
Settings elegante tipo iOS, Figma, Notion. Claro, bem organizado, profissional.

## Método de verificação
- Nível: 2 (interactive)
- Ferramenta: App emulador, teste de toggles, dropdowns, confirmações

### Roteiro de experiência
1. Abrir app, navegar para Settings
2. Ver layout (seções claras? Toggles visíveis?)
3. Clicar toggle → muda de on para off?
4. Abrir dropdown → opcões aparecem clara?
5. Clicar logout → confirmação aparece?
6. Tirar screenshot (comparar com benchmark)
7. Dark mode → tudo legível?

## Histórico de notas
| Rodada | Nota | Status |
|---|---|---|
| 1 | — | pending |
