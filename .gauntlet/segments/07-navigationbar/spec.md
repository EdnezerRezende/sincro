# Segmento 07 — NavigationBar (Bottom Nav / Drawer)

- **Onda**: 1
- **Depende de**: 00-design-system
- **Escopo de arquivos**: `mobile/lib/core/widgets/app_navigation.dart` ou similar

## Entregável
Navegação principal (bottom nav em mobile, drawer em tablet+) com:
- Tabs: Home, Email, Biofeedback, Finanças, Settings (ou conforme specs)
- Ícones + labels em mobile
- Estados: active (cor), inactive (cinza)
- Animação ao trocar tab (smooth transition)
- Badge para notificações (ex: 3 emails)

## Critérios de aceitação
1. Tabs selecionada tem cor primária e está clara
2. Tabs não selecionada é cinza/opaca
3. Ícones são 24x24 dp, labels são pequenas (12 sp aprox)
4. Altura é 56–64 dp (material standard)
5. Gap entre tabs é igual, sem apertado
6. Badge (notificação) é visível e pequeno (12x12 aprox)
7. Transição ao clicar uma tab é suave (200ms)
8. Dark mode: cores legíveis

## Benchmark
Material Design 3 BottomNavigationBar. Claro, espaçado, profissional.

## Método de verificação
- Nível: 2 (interactive)
- Ferramenta: App emulador, teste de toque entre tabs

### Roteiro de experiência
1. Abrir app na home screen
2. Ver navigation bar na base
3. Clicar em cada tab → transição é suave?
4. Observar tab ativa → cor é clara?
5. Abrir tela que tem notificação (ex: 3 emails novos)
6. Voltar para home → badge aparece no tab "Email"?
7. Testar dark mode → cores claras?

## Histórico de notas
| Rodada | Nota | Status |
|---|---|---|
| 1 | — | pending |
