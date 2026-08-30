# Segmento 13 — Home Screen Layout (Estrutura Principal)

- **Onda**: 2
- **Depende de**: 06-appbar, 07-navigationbar, 08-scaffold-layout, 02-component-card
- **Escopo de arquivos**: `mobile/lib/features/home/home_screen.dart`, `mobile/lib/features/home/home_layout_mode.dart`

## Entregável
Home screen redesenhada com:
- Greeting customizado (nome do usuário, time do dia)
- Cards/seções: email summary, finanças, biofeedback, contatos, cards sensorial
- Suporte a 2 layouts (Resumo / Abas conforme specs)
- Floating action button ou button "Avisar Rede" em destaque
- Espaçamento consistente entre cards (16 dp gap)
- Scroll smooth quando conteúdo > viewport
- Sem aglomeração sensorial

## Critérios de aceitação
1. Greeting é personalizado (nome do usuário visível)
2. Cards são espaçados (gap >= 16 dp)
3. Cada card/seção tem título claro e ícone visual
4. Layout alternativo (Resumo/Abas) pode ser toggled
5. Floating action button é claro e acessível (48x48 dp mínimo)
6. Cores de cards são harmônicas (não arco-íris)
7. Scroll é smooth (sem jank)
8. Dark mode funciona
9. Conteúdo placeholder é claro (ex: "Gmail não conectado" com CTA)
10. Sem overflow de texto — content respira

## Benchmark
Home screen alegre mas profissional, tipo Slack, Figma, Notion. Limpo, bem estruturado.

## Método de verificação
- Nível: 2 (screenshot + interactive)
- Ferramenta: App emulador, teste de layout modes, scroll

### Roteiro de experiência
1. Abrir app pós-login (home screen deve carregar)
2. Ver layout (greeting visível? Cards bem espaçados?)
3. Tirar screenshot (comparar com benchmark)
4. Scroll down → conteúdo inteiro acessível?
5. Trocar layout mode (Resumo/Abas) → visual muda?
6. Dark mode → cores ainda harmônicas?
7. Testar em 375px e 768px → layout responde bem?

## Histórico de notas
| Rodada | Nota | Status |
|---|---|---|
| 1 | — | pending |
