# Segmento 08 — Scaffold Layout (Base de Todas as Telas)

- **Onda**: 1
- **Depende de**: 00-design-system, 06-appbar, 07-navigationbar
- **Escopo de arquivos**: `mobile/lib/core/widgets/app_scaffold.dart` ou similar

## Entregável
Scaffold reutilizável (composição AppBar + body + NavigationBar) com:
- Safe area respeitada (notch, bottom inset)
- Padding e espaçamento consistente
- Body scrollável ou não conforme necessário
- Floating action button (se aplicável)
- Suporte a múltiplos temas

## Critérios de aceitação
1. Todos os screens usam o mesmo Scaffold (sem custom AppBar/Nav)
2. Safe area é respeitada (conteúdo não sobrepõe notch/home indicator)
3. Padding é consistente (16 dp do edge em mobile)
4. Body scrollável se conteúdo > viewport height
5. Transitions entre screens são suaves (não jarring)
6. AppBar + Nav + body layout é sempre o mesmo ordem
7. Dark mode funciona em todas as telas
8. Responsividade: Scaffold adapta para tablet (drawer em vez de bottom nav?)

## Benchmark
Scaffold padrão Material Design bem executado. Consistência visual completa.

## Método de verificação
- Nível: 2 (visual consistency check)
- Ferramenta: App emulador, rodar vários screens e comparar

### Roteiro de experiência
1. Abrir home screen
2. Tirar screenshot (AppBar, body, nav bar visíveis?)
3. Navegar para Settings screen
4. Tirar screenshot (mesmo layout, só muda conteúdo?)
5. Navegar para Email detail
6. Tirar screenshot (AppBar tem back? Body é conteúdo email?)
7. Comparar 3 screenshots → Scaffold é realmente consistente?

## Histórico de notas
| Rodada | Nota | Status |
|---|---|---|
| 1 | — | pending |
