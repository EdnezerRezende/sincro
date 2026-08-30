# Segmento 02 — Componente Card (Base para Conteúdo)

- **Onda**: 0
- **Depende de**: 00-design-system
- **Escopo de arquivos**: `mobile/lib/core/widgets/app_card.dart`

## Entregável
Card reutilizável com:
- Fundo branco/luz com sombra sutil ou border
- Padding interno consistente (16 dp)
- Suporta título, subtitle, ícone, ações
- Variant: elevado (sombra) ou plano (border)
- Estados: normal, hover, selected
- Espaçamento entre cards >= 16 dp

## Critérios de aceitação
1. Card tem sombra ou border visível (não invisível)
2. Padding interno é consistente em todos os cards (16 dp recomendado)
3. Título e conteúdo têm hierarquia clara (tamanho/peso diferente)
4. Estado selected tem feedback visual (cor de fundo, border, check)
5. Cards não se tocam — gap mínimo 16 dp entre eles
6. Dark mode: card é visível contra fundo (contraste OK)
7. Clicável: card inteiro é tátil ou apenas botão dentro? Deve ser claro.
8. Sem overflow de texto — content respira

## Benchmark
Card elegante tipo Notion, Figma ou Apple Notes. Simples, limpo, com boa hierarquia.

## Método de verificação
- Nível: 1 (screenshot)
- Ferramenta: App emulador, light/dark mode

### Roteiro de experiência
1. Abrir Home screen ou any page com cards (email list, grounding cards, etc)
2. Tirar screenshot
3. Observar: cards têm espaçamento consistente?
4. Observar: sombra/border é clara?
5. Observar: títulos e conteúdo têm hierarquia?
6. Ligar dark mode, screenshot novamente
7. Observar: cards ainda legíveis? Sombra ainda funciona?

## Histórico de notas
| Rodada | Nota | Status |
|---|---|---|
| 1 | — | pending |
