# MISSÃO — Sincro Frontend: UI/UX para Neurodivergência (TEA/TDAH)

## Meta
Redesenhar o frontend Sincro para ser uma experiência visual agradável, dinamicamente responsiva e moderna, otimizada especificamente para usuários autistas (TEA) e com TDAH, respeitando as specs existentes e os princípios de acessibilidade neurodivergente.

## Benchmark concreto

**Padrão visual:** Design alegre + moderno + profissional, sem exageros.

**Princípios de referência:**
- **Alegria sem ruído:** paleta vibrante mas harmônica (não arco-íris), animations refinadas que trazem vida
- **Moderno:** componentes clean, tipografia clara, espaçamento deliberado, sem skeuomorphism datado
- **Profissional:** não parece um app para crianças; confiança transmitida por consistência e polish
- **Sem exageros:** nada piscante, frenético ou que distraia do objetivo do usuário; cada elemento tem propósito
- **Clareza visual:** hierarquia óbvia, sem competição por atenção entre elementos
- **Acessibilidade neurodivergente:** espaçamento generoso, densidade textual baixa, feedback imediato, consistência de padrões

**O que estamos comparando:**
- Densidade visual (quantos elementos competem pela atenção?)
- Paleta e harmonia (cores trabalham juntas ou gritam isoladamente?)
- Animações e transições (refinadas e propositais, não decorativas)
- Tipografia e legibilidade (fácil ler? Fácil escanear?)
- Consistência (botões sempre iguais? Padrões repetidos ou improvisados?)

## Critérios de aceitação globais
1. **Nenhum elemento "invisible" por padrão** — toda ação necessária está visível sem scroll oculto ou UI elementos escondidos atrás de gestos não intuitivos.
2. **Paleta reduzida e consistente** — máximo 5–6 cores base + variações, documentadas no tema Flutter. Sem gradientes caóticos ou cores aleatórias por feature.
3. **Nenhuma animação frenética ou irritante** — transições são suaves (duration >= 300ms), não piscam, não causam desconforto.
4. **Tamanho de touch targets >= 48x48 dp** em toda parte mobile-only, gaps >= 16 dp entre clicáveis.
5. **Densidade textual controlada** — nenhuma linha com >12 palavras; cabeçalhos claros; campos de entrada com placeholders informativos.
6. **Feedback tátil/visual imediato** — botões pressionados, estados carregando, erros claros, sem ambiguidade.
7. **Contraste WCAG AA mínimo** — texto legível em fundo, sem false claims de "modo escuro" que reduz legibilidade.
8. **Responsividade** — mesmo design funciona em 375x812 (iPhone SE) até 768x1024 (tablets), sem quebras.
9. **Jornada onboarding clara** — primeiros 2 minutos no app não confundem; cada tela tem 1 ação primária óbvia.
10. **Nenhuma ação irreversível sem confirmação** — apagar contatos, desconectar Gmail, etc. sempre têm modal de dupla confirmação.

## Restrições
- **Stack:** Flutter mobile (iOS/Android), não alterar arquitetura backend.
- **Plataforma:** iOS 14+ e Android 7+. Sem quebras em viewports comuns.
- **Não fazer:**
  - Adicionar novas features (specs já existem, não inventar). Apenas revisar/polir UI.
  - Alterar lógica de negócio ou comportamentos não-visuais.
  - Quebrar nenhuma integração (Google Sign-In, Gmail OAuth, Pluggy, HealthKit, etc.).
- **Must-respect:** Tema customizável existente (`core/theme.dart`), design system de cores/spacing.

## Contratos compartilhados (builders não alteram)
| Item | Definição |
|---|---|
| **Paleta de cores** | Extraída dos assets: ciano/turquesa vibrante (primária), azul profundo (secundária), branco, cinza escuro. Nenhuma cor nova sem aprovação. |
| `core/theme.dart` | Tokens de cor, tipografia, spacing. Pode ser estendido, nunca quebrado. Refletir paleta dos assets. |
| Branding visual | Logo e tagline "Apoio silencioso para o seu ritmo" — tom calmo, elegante, profissional. |
| Rutas de navegação | `onboarding_router.dart`, `home_screen.dart`, etc. mantêm nomes e parâmetros. |
| API responses | `features/*/models` não sofrem breaking changes. |

## Orçamento
- **max_rounds:** 3 (como solicitado com `--rounds 3`)
- **Teto de tempo:** ~4–6h (Gauntlet é computacionalmente intensivo; cada rodada envolve múltiplos builders + verificadores em paralelo)
- **Teto de tokens:** ~600k (verificação cega é cara; múltiplas telas testadas, screenshots, feedback detalhado)
- **Barra de aprovação:** `score >= 90` **E** `impressed == true`

## Suposições assumidas
- O usuário quer revisar **todo** o frontend (todas as telas, todos os features), não apenas uma seção.
- O benchmark é **acessibilidade neurodivergente** primeiro, design moderno segundo — não estilo corporativo minimalista.
- As specs de features (anamnese, email triage, home layout modes) são corretas e não mudam; o problema é *como* elas são apresentadas visualmente.
- Verificadores testarão no device real (iOS/Android) ou emulador, não apenas lerão código.
- Iterações esperam melhoria real de "agradar + dinâmico + moderno" (subjetivo), não só "sem erros" (técnico).
