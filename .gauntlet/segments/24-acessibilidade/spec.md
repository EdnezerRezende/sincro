# Segmento 24 — Acessibilidade (Contraste, Toque, Keyboard)

- **Onda**: 4
- **Depende de**: todos (00–22)
- **Escopo de arquivos**: `mobile/lib` (tema, componentes, screens)

## Entregável
Toda UI testada com:
- Contraste WCAG AA mínimo (4.5:1 para texto)
- Touch targets >= 48x48 dp (buttons, inputs)
- Gaps entre táteis >= 16 dp
- Keyboard navigation (TAB entre elementos)
- Semantic labels (buttons têm text/label, inputs têm label)
- Focus states claros (border, cor, shadow)

## Critérios de aceitação
1. Texto em fundo sempre tem contraste >= 4.5:1 (teste com Contrast Checker)
2. Todos botões são >= 48x48 dp (medido com devtools)
3. Gaps entre botões/táteis são >= 16 dp
4. Tab key navega por elementos interativos (ordem lógica)
5. Focus state é claro (ring, cor, shadow — não invisível)
6. Buttons têm text ou semantic label (não só ícone sem context)
7. Inputs têm label acima (não só placeholder)
8. Icons têm alt text ou label associado
9. Dark mode mantém contraste (não usa preto puro + preto)
10. Modais focam no modal (não atrás)

## Benchmark
Qualidade acessibilidade tipo Apple, Google Material Design. Compliant com WCAG 2.1 Level A.

## Método de verificação
- Nível: 3 (automated + manual testing)
- Ferramenta: Contrast checker, devtools accessibility inspector, keyboard testing

### Roteiro de experiência
1. Abrir cada screen
2. Usar eyedropper + contrast checker em pares texto/fundo
3. Medir sizes de buttons (devtools inspector)
4. Testar keyboard tab navigation (cada elemento fica focado?)
5. Focus state é claro? Invisível?
6. Testar dark mode (contraste ainda OK?)
7. Abrir acessibilidade tree (devtools) → labels aparecem?

## Histórico de notas
| Rodada | Nota | Status |
|---|---|---|
| 1 | — | pending |
