# Segmento 04 — Componente Chip (Selecionável)

- **Onda**: 0
- **Depende de**: 00-design-system
- **Escopo de arquivos**: `mobile/lib/core/widgets/app_chip.dart` ou similar

## Entregável
Chip reutilizável com:
- Variantes: input (selecionável), suggestion (recomendação), filter (toggle)
- Estados: default, selected, disabled
- Tamanho: fit content, com padding horizontal 12 dp, altura ~36 dp
- Ícone opcional antes ou depois do texto
- Sem abreviar texto (quebra em 2 linhas se necessário)
- Feedback visual ao selecionar (cor, background)

## Critérios de aceitação
1. Chip selecionado tem cor/background claro (não é ambíguo)
2. Chip não selecionado é visualmente distinto (outline ou cor pálida)
3. Espaçamento entre chips é consistente (gap >= 8 dp)
4. Estados disabled ficam visivamente mortos (opacidade, sem interação)
5. Texto não trunca — quebra se necessário ou redimensiona chip
6. Touch target >= 36 dp altura
7. Ícones têm espaçamento de 8 dp do texto
8. Dark mode: cores ainda legíveis e distintas

## Benchmark
Material Design 3 Chip ou componente de boa qualidade (Figma, Slack). Clara hierarquia de seleção.

## Método de verificação
- Nível: 2 (interactive)
- Ferramenta: App emulador, teste de múltipla seleção

### Roteiro de experiência
1. Abrir tela com chips selecionáveis (anamnese wizard, filtros, etc)
2. Clicar em chip → muda para selected state?
3. Clicar de novo → volta ao não selecionado?
4. Selecionar múltiplos chips → cada um mostra estado distinto?
5. Observar disabled chip → não responde ao toque?
6. Tirar screenshot com vários chips → espaçamento consistente?
7. Testar em dark mode → cores claras?

## Histórico de notas
| Rodada | Nota | Status |
|---|---|---|
| 1 | — | pending |
