# Decomposição — Sincro Frontend

## Ondas de Paralelismo

### Onda 0: Fundações (sem dependências)
- **00-design-system**: Tema, cores, tipografia, spacing tokens
- **01-component-button**: Botão reutilizável em todos os estados
- **02-component-card**: Card base para conteúdo
- **03-component-input**: Input text, com validação visual e feedback
- **04-component-chip**: Chips selecionáveis (usado em anamnese, filtros)
- **05-component-modal**: Modal de confirmação, alertas

### Onda 1: Navegação, Containers e Apresentação (depende de componentes base)
- **06-splash-screen-dynamic**: Splash screen animado na abertura do app
- **07-appbar**: Header com título, ícones e ações
- **08-navigationbar**: Bottom nav ou drawer principal
- **09-scaffold-layout**: Scaffold base que todo screen herda
- **10-loading-state**: Estados de carregamento (skeleton, spinner)
- **11-error-state**: Telas/widgets de erro
- **12-empty-state**: Estados vazios com ilustrações

### Onda 2: Telas de Acesso (depende de navegação + componentes)
- **13-auth-flow**: LoginScreen + SignupScreen UI
- **14-home-screen-layout**: Estrutura home (resumo, cards, seções)
- **15-settings-screen**: Settings visual (lista, toggles, ações)

### Onda 3: Principais Features (depende de Onda 2)
- **16-onboarding-anamnese**: Wizard steps, progress visual
- **17-email-inbox**: Email list, card summary, categorias visuais
- **18-biofeedback-screen**: Gráficos, cards de métrica, alerts visuais
- **19-finances-screen**: Resumo financeiro, cards de categoria
- **20-trusted-contacts**: Lista de contatos, add/remove UI
- **21-grounding-cards**: Card grid, detalhe card, sugestões visuais
- **22-guide-screen**: Conteúdo educativo, navegação
- **23-professionals-search**: Search, lista profissionais, filtros

### Onda 4: Qualidade Transversal (depende de tudo acima)
- **24-responsividade**: Layout funciona 375px–768px
- **25-acessibilidade**: Contraste, touch targets, keyboard nav
- **26-animacoes**: Transições, microinterações (press, states)

## Dependências (grafo reduzido)
```
Onda 0 (00–05): nenhuma
  ↓
Onda 1 (06–11): 00–05
  ↓
Onda 2 (12–14): 06–11
  ↓
Onda 3 (15–22): 12–14
  ↓
Onda 4 (23–25): tudo
```

Total: **27 segmentos** em **5 ondas** (qualidade transversal na onda final).
