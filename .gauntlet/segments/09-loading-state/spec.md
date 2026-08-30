# Segmento 09 — Loading State (Skeleton / Spinner)

- **Onda**: 1
- **Depende de**: 00-design-system, 02-component-card
- **Escopo de arquivos**: `mobile/lib/core/widgets/loading_widget.dart` ou similar

## Entregável
Loading UI reutilizável com:
- Skeleton cards que mimic o layout real (fake cards/titles/texts)
- Shimmer animation suave (gradiente indo e vindo)
- Spinner para loading modal
- Estados: page loading, list loading, inline loading

## Critérios de aceitação
1. Skeleton é proporcional ao layout real (não aleatório)
2. Shimmer é suave (1–2s duration, não frenético)
3. Skeleton desaparece quando conteúdo real chega (sem jitter)
4. Spinner é centrado e legível
5. Animação é acessível (sem piscadas/flickering)
6. Cores do skeleton combinam com tema (não preto puro)
7. Dark mode: skeleton legível
8. Carregamento nunca fica preso (timeout visível? Retry botão?)

## Benchmark
Skeleton bem feito tipo Figma, Slack. Transições suaves, sem choque ao aparecer conteúdo.

## Método de verificação
- Nível: 2 (interactive + network throttle)
- Ferramenta: App emulador + devtools para throttle network

### Roteiro de experiência
1. Abrir app (home carrega com skeleton? Email list carrega com skeleton?)
2. Observar skeleton animation (shimmer é suave? Cores OK?)
3. Esperar conteúdo carregar (skeleton desaparece sem jitter?)
4. Throttle network (devtools) e recarregar (loading UI aparece?)
5. Tirar screenshot com skeleton visível
6. Comparar com benchmark (aparência profissional?)

## Histórico de notas
| Rodada | Nota | Status |
|---|---|---|
| 1 | — | pending |
