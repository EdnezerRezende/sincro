# Segmento 00 — Design System (Tema, Cores, Tipografia)

- **Onda**: 0
- **Depende de**: nenhum
- **Escopo de arquivos**: `mobile/lib/core/theme.dart`, `mobile/lib/core/app_colors.dart` (se existir), documentação

## Entregável
Tema Flutter completo documentado com:
- **Paleta extraída dos assets:** ciano/turquesa (primária), azul profundo (secundária), branco, cinza escuro + variações de tom
- Tipografia (heading, body, caption) com escalas claras
- Spacing tokens (8, 16, 24, 32 dp)
- Sombras/elevação consistentes
- Estados de hover/focus/disabled
- Modo escuro automático e testado
- Documentação de hex codes e significado funcional de cada cor

## Critérios de aceitação
1. **Paleta extraída dos assets existentes** (ciano/turquesa, azul profundo, branco, cinza escuro) — nenhuma cor nova
2. Paleta documentada com códigos hex e significado funcional (primária, secundária, erro, sucesso, etc.)
3. Tipografia tem escalas legíveis (16–18 body, 20–24 heading, 12–14 caption)
4. Contraste >= WCAG AA em todos os pares cor/fundo (verificado em ferramenta)
5. Spacing usa múltiplos de 8 dp em toda parte (nenhum tamanho aleatório)
6. Dark mode automático em iOS/Android respeita preferência do sistema
7. Todos os tokens são `const`, não hardcoded em widgets

## Benchmark
Paleta harmônica tipo Figma, Slack ou Notion — cores que transmitem profissionalismo mas acessíveis visualmente (não muito saturadas, boa contrast). Tipografia clara e legível em 375px até 768px.

**⚠️ NOTA CRÍTICA:** Atualmente, `theme.dart` define cores (verde, cinza, terracota) que **NÃO CORRESPONDEM** ao branding visual dos assets (ciano/turquesa vibrante). O builder **DEVE** alinhar o theme.dart com o branding dos assets, ou documentar explicitamente a discrepância para decisão do usuário.

## Método de verificação
- Nível: 2 (leitura + screenshot)
- Ferramenta: Editor de código + app no emulador com dark mode ligado/desligado

### Roteiro de experiência
1. Ler `core/theme.dart` e documentar paleta observada
2. Abrir app em emulador (light mode)
3. Tirar screenshot de uma tela com texto, botão, card
4. Verificar contraste com [contrast checker](https://webaim.org/resources/contrastchecker/)
5. Ligar dark mode no sistema e retomar o app
6. Observar: cores ainda legíveis? Sombras funcionam? Nenhum elemento fica invisível?
7. Comparar com: Figma, Slack — paleta coerente? Tipografia escalada?

## Histórico de notas
| Rodada | Nota | Status |
|---|---|---|
| 1 | — | pending |
