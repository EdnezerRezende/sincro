# Decomposição Completa — 27 Segmentos

## Resumo por Onda

### Onda 0: Fundações (6 segmentos) — sem dependências
| ID | Nome | Entregável |
|---|---|---|
| 00 | Design System | Tema, cores, tipografia, spacing tokens |
| 01 | Button Component | Botão reutilizável em todos os estados |
| 02 | Card Component | Card base para conteúdo |
| 03 | Input Component | Input text com validação visual |
| 04 | Chip Component | Chips selecionáveis (anamnese, filtros) |
| 05 | Modal Component | Modal de confirmação e alertas |

### Onda 1: Navegação, Containers e Apresentação (7 segmentos) — depende de Onda 0
| ID | Nome | Entregável |
|---|---|---|
| 06 | Splash Screen Dinâmico | Logo animado + transição suave para auth |
| 07 | AppBar | Header principal com ações |
| 08 | NavigationBar | Bottom nav ou drawer |
| 09 | Scaffold Layout | Base de todas as telas |
| 10 | Loading State | Skeleton + shimmer + spinner |
| 11 | Error State | Telas de erro amigável |
| 12 | Empty State | Estados vazios com CTA |

### Onda 2: Telas de Acesso (3 segmentos) — depende de Onda 1
| ID | Nome | Entregável |
|---|---|---|
| 13 | Auth Flow | LoginScreen + SignupScreen |
| 14 | Home Screen | Estrutura home com cards e layout modes |
| 15 | Settings Screen | Configurações e opções |

### Onda 3: Features Principais (8 segmentos) — depende de Onda 2
| ID | Nome | Entregável |
|---|---|---|
| 16 | Anamnese Wizard | Onboarding sensorial com steps |
| 17 | Email Inbox | Lista + detail de emails |
| 18 | Biofeedback | Métricas + gráficos |
| 19 | Finances | Resumo financeiro + categorias |
| 20 | Trusted Contacts | Rede de apoio, avisos |
| 21 | Grounding Cards | Alívio sensorial, cards interativos |
| 22 | Guide Screen | Conteúdo educativo |
| 23 | Professionals Search | Busca de profissionais + detail |

### Onda 4: Qualidade Transversal (3 segmentos) — depende de TUDO
| ID | Nome | Entregável |
|---|---|---|
| 24 | Responsividade | Layout funciona 375–768px |
| 25 | Acessibilidade | Contraste, touch, keyboard WCAG AA |
| 26 | Animações | Transições suaves, microinterações |

---

## Fluxo de Parallelismo

```
Onda 0 (6 segmentos)
  ↓ paralelo
Onda 1 (7 segmentos) ← +1 Splash Screen
  ↓ paralelo
Onda 2 (3 segmentos)
  ↓ paralelo
Onda 3 (8 segmentos)
  ↓ paralelo
Onda 4 (3 segmentos)
```

**Total:** 27 segmentos em 5 ondas sequenciais.
**Paralelismo máximo:** Onda 3 com 8 executores simultâneos.

---

## Próximas Fases

✅ **Fase 1 (Decomposição) — COMPLETA**

👉 **Fase 2 (Harness):** Decidir como cada segmento será verificado e instalar ferramentas necessárias.

✅ **Confirmação do usuário:** Algum segmento faltando? Algum que deveria ser dividido mais?
