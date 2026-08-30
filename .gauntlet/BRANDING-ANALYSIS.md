# Análise de Branding — Sincro

## Paleta Extraída dos Assets

### Cores Primárias (conforme logos e splash)
| Cor | Nome | Uso | Hex Aproximado |
|---|---|---|---|
| 🔵 Ciano Vibrante | Primary | Logo, tagline, elementos de destaque | `#00BCD4` ou `#0ABDC7` |
| 🔷 Azul Profundo | Secondary | Sombras do logo, profundidade | `#1A3A52` ou `#0D5B82` |
| ⚪ Branco | Surface | Fundo e contraste | `#FFFFFF` |
| ⚫ Cinza Escuro | Dark Background | Fundo de splash (dark mode) | `#1A2332` |

### Tagline
**"Apoio silencioso para o seu ritmo"**
- **Tom:** Calmo, empático, sincronizado
- **Aplicação:** Reflete a proposta para neurodivergentes (silencioso = sem sobrecarga sensorial; ritmo = respeito ao tempo individual)

### Logo
**"S" fluido e dinâmico**
- **Significado:** Movimento, fluxo, ritmo sincronizado
- **Paleta:** Gradiente ciano → azul profundo com branco para contraste
- **Elegância:** Profissional mas acessível

---

## Desalinhamento Atual

### Problema
O `theme.dart` atual (verde #3F7268, cinza #64748B, terracota #B4672E) **NÃO** reflete o branding visual dos assets (ciano/azul).

### Impacto
- App não transmite visualmente a identidade que os assets estabelecem
- Confusão entre branding visual (moderno, ciano) e implementação (verde/terracota)
- Potencial falta de coerência na percepção do app

### Decisão Necessária (Segmento 00)
1. **Opção A:** Atualizar `theme.dart` para usar ciano/azul dos assets (recomendado)
2. **Opção B:** Manter cores atuais mas justificar em design doc
3. **Opção C:** Híbrido — usar ciano como primária, manter verde/terracota como variações semânticas

---

## Recomendação para Builders

**Todos os segmentos (01–25) devem usar a paleta de cores estabelecida no segmento 00 (design-system).**
- Se 00 escolher Opção A (recomendado): todos usarão ciano/azul
- Se 00 escolher Opção B/C: seguir conforme definido

**Validação:** No segmento 24 (acessibilidade), verificar contraste WCAG AA entre ciano/azul e fundos (light/dark).

---

## Nota para Verificadores

Ao julgar segmento 00 (design-system), avaliar:
1. Paleta documentada com hex codes
2. Alinhamento (ou justificativa) com branding dos assets
3. Tipografia legível em múltiplos tamanhos
4. Contraste WCAG AA em todos os pares cor/fundo
5. Dark mode coerente e não fatigante
