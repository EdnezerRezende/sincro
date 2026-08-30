# Segmento 01 — Componente Button (Reutilizável)

- **Onda**: 0
- **Depende de**: 00-design-system
- **Escopo de arquivos**: `mobile/lib/core/widgets/app_button.dart` (ou similar)

## Entregável
Componente Button reutilizável com:
- Variantes: primário, secundário, outline, texto
- Estados: normal, hover, pressed, disabled, loading
- Tamanhos: small (36 dp), medium (48 dp), large (56 dp)
- Ícone opcional à esquerda/direita
- Todos os estados com feedback visual claro (cor, elevação, ripple/scale)

## Critérios de aceitação
1. Botão primário é claro e atraente (cor primária do tema)
2. Botão desabilitado é visualmente distinto (opacidade, cor acinzentada)
3. Estado pressed tem feedback tátil: scale down 2–5% ou mudança de elevação
4. Hover state (desktop/tablet) é sutil mas notável (mudança de elevação ou cor)
5. Ripple/splash effect respeita forma do botão (sem overflow)
6. Tamanho mínimo de touch target é 48x48 dp (mobile)
7. Botão com loading mostra spinner dentro, texto desaparece ou fica opaco
8. Ícones internos são alinhados e espaçados de forma consistente

## Benchmark
Material Design 3 button ou componente de alta qualidade (iOS HIG). Feedback imediato, sem ambiguidade de estado.

## Método de verificação
- Nível: 2 (interactive testing)
- Ferramenta: App emulador, teste tátil

### Roteiro de experiência
1. Abrir app, encontrar 2–3 botões de diferentes tipos (primário, secundário, desabilitado)
2. Clicar em botão primário → observar feedback (scale, elevação, ripple)
3. Observar botão desabilitado → deve estar visualmente morto (sem hover)
4. Se tiver botão com loading → clicar e observar spinner
5. Comparar com Material 3 → feedback é claro e refinado?
6. Testar em 2 tamanhos: 375px e 768px → botão permanece tocável?

## Histórico de notas
| Rodada | Nota | Status |
|---|---|---|
| 1 | — | pending |
