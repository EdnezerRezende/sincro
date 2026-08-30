# Segmento 23 — Responsividade (Layout 375–768px)

- **Onda**: 4
- **Depende de**: todos (00–22)
- **Escopo de arquivos**: `mobile/lib` (todos os widgets respeitar MediaQuery)

## Entregável
Todas as telas testadas e funcionais em:
- 375x812 (iPhone SE, pequeno)
- 414x896 (iPhone 13)
- 768x1024 (iPad mini, tablet)

Sem overflow, sem elementos cortados, layout adapta sensatamente.

## Critérios de aceitação
1. Nenhum elemento overflow em 375px (sem horizontal scroll)
2. AppBar cabe sem cortar botões
3. Botões são táteis (48x48 dp mínimo) em todos os tamanhos
4. Texto não fica minúsculo em tablets (escala bem)
5. Cards em grid reduzem colunas em tamanhos pequenos (2 em 375px, 3+ em 768px)
6. Padding adapta (16dp em small, 24dp em large)
7. Modals e popups centralizam bem
8. Nenhuma font size abaixo de 12sp em body text
9. Landscape mode funciona (se app suporta)
10. Sem layout shifts ao carregar/scroll

## Benchmark
iOS/Android adaptive layouts. Apps profissionais que funcionam fluentemente em múltiplos tamanhos.

## Método de verificação
- Nível: 2 (screenshot em múltiplos tamanhos)
- Ferramenta: Emulador (landscape + portrait), múltiplos presets de device

### Roteiro de experiência
1. Rodar app em emulador com preset 375px
2. Navegar por todas as telas
3. Tirar screenshot de home, email, settings, etc
4. Observar: nada overflow? Texto legível?
5. Rodar em 768px (iPad)
6. Observar: layout adapta? Cards em mais colunas?
7. Rodar em landscape (se suporta)
8. Observar: layout ainda funciona?

## Histórico de notas
| Rodada | Nota | Status |
|---|---|---|
| 1 | — | pending |
