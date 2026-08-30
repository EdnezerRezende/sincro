# Segmento 25 — Animações e Microinterações

- **Onda**: 4
- **Depende de**: todos (00–22)
- **Escopo de arquivos**: `mobile/lib` (screens, componentes com transições)

## Entregável
Todas as telas e transições com animações suaves:
- Page transitions (200–300ms, slide ou fade)
- Button press feedback (scale 2–5%, ripple)
- Loading states (shimmer suave)
- Chip selection (color change smooth)
- Modal entrada/saída (fade+scale)
- Scroll animações (parallax suave, se houver)

## Critérios de aceitação
1. Page transitions não são instantâneas (200–300ms)
2. Transitions são suave (não jarring, easing curve OK)
3. Button press tem visual feedback (não morto)
4. Loading shimmer é fluido (não piscante)
5. Modal abre/fecha com animação (não popup súbito)
6. Chip selection muda cor smoothly (não snap)
7. Nenhuma animação > 500ms (chata)
8. Nenhuma animação frenética (velocidade OK)
9. Animações respeitar performance (60 fps, não lag)
10. Sem animações que causam desconforto (piscadas, parallax extremo)

## Benchmark
Material Design 3 transitions. Polidas, fluidas, propositais (não por decoração).

## Método de verificação
- Nível: 3 (interactive + performance profiling)
- Ferramenta: App emulador, devtools profiler (jank detection)

### Roteiro de experiência
1. Abrir app (inicialização tem animação?)
2. Navegar entre tabs → transição é suave?
3. Clicar botão → feedback é imediato e suave?
4. Clicar chip → seleção anima?
5. Carregar conteúdo → shimmer é fluido?
6. Abrir modal → anim entrada é suave?
7. Fechar modal → anim saída é OK?
8. Devtools profiler → FPS constante 60? Nenhum jank?

## Histórico de notas
| Rodada | Nota | Status |
|---|---|---|
| 1 | — | pending |
