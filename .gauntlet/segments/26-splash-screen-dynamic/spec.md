# Segmento 26 — Splash Screen Dinâmico (Abertura do App)

- **Onda**: 1
- **Depende de**: 00-design-system
- **Escopo de arquivos**: `mobile/lib/core/widgets/splash_screen.dart`, `mobile/lib/main.dart` (inicialização)

## Entregável
Splash screen dinâmico que aparece na abertura do app (antes de SignIn/SignUp) com:
- Logo animado (fade-in, scale suave, ou outro efeito refinado)
- Tagline "Apoio silencioso para o seu ritmo" (opcional, pode aparecer com fade)
- Fundo com paleta do branding (ciano/azul ou escuro conforme dark mode)
- Duração: 2–3 segundos
- Transição suave para auth screen
- Sem jank/lag na animação
- Acessível (sem piscadas irritantes)

## Critérios de aceitação
1. Logo é centralizado e tem animação suave (não instantâneo)
2. Paleta de cores do branding é respeitada (ciano/azul + fundo apropriado)
3. Animação é fluida (60 fps, sem jank)
4. Duração é sensível (2–3s, não muito longo)
5. Transição para auth é suave (não jarring)
6. Dark mode: splash ainda vibrante e legível
7. Tagline (se presente) é legível e animada apropriadamente
8. Nenhuma piscada ou efeito desconfortável (importante para neurodivergentes)
9. App está pronto para interação após splash (não fica preso)
10. Animação não causa lag em devices baixa spec

## Benchmark
Splash moderno tipo Figma, Slack, Notion. Elegante, breve, que transmite identidade da marca.

## Método de verificação
- Nível: 2 (interactive + performance)
- Ferramenta: App emulador, devtools profiler para FPS, teste de duração com cronômetro

### Roteiro de experiência
1. Fechar app completamente (kill process)
2. Abrir app fresh → splash aparece?
3. Observar: logo é centralizado? Animação é suave?
4. Observar: duração é apropriada (nem muito rápido, nem muito lento)?
5. Observar: transição para auth é suave?
6. Devtools profiler → FPS em 60 durante splash?
7. Dark mode: splash ainda bonito? Legível?
8. Tirar screenshot (compare com benchmark visual)

## Histórico de notas
| Rodada | Nota | Status |
|---|---|---|
| 1 | — | pending |
