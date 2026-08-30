# Segmento 20 — Grounding Cards (Alívio Sensorial)

- **Onda**: 3
- **Depende de**: 02-component-card, 01-component-button, 08-scaffold-layout
- **Escopo de arquivos**: `mobile/lib/features/grounding_cards/grounding_cards_library_screen.dart`, `mobile/lib/features/grounding_cards/grounding_card_detail_screen.dart`

## Entregável
Grounding cards library redesenhada com:
- Grid de cards com imagem/ícone, título, categoria
- Categorias: sensorial (5 sentidos), movimento, respiração, etc
- Filter/search por categoria
- Detail screen com instruções passo-a-passo
- Timer se necessário (respiração cronometrada)
- Sugestões personalizadas baseadas em stress level

## Critérios de aceitação
1. Grid é responsivo (2-3 colunas conforme tamanho de tela)
2. Cards têm imagem/ícone visual alegre (não triste)
3. Título é legível (não truncado)
4. Categoria é clara (ícone + label)
5. Clique em card → detail screen com instruções
6. Instruções são passo-a-passo (numeradas, claras, sem jargão)
7. Timer (se houver) é grande e legível
8. Sugestões personalizadas são contextuais (ex: high stress → técnica calmante)
9. Dark mode funciona (imagens legíveis)
10. Nenhum conteúdo assustador (tudo alegre/calmo)

## Benchmark
Headspace, Calm app. Visuais alegres, instruções claras, interface calmante.

## Método de verificação
- Nível: 3 (interactive + timer test)
- Ferramenta: App emulador, teste de grid, detail, timer

### Roteiro de experiência
1. Abrir Grounding Cards (no home card ou tab)
2. Ver grid de cards (imagens claras? Títulos legíveis?)
3. Clicar em card → detail screen aparece?
4. Observar: instruções são passo-a-passo?
5. Se timer existir: iniciar → conta regressivo?
6. Filter por categoria → grid muda?
7. Tirar screenshot (compare com Headspace/Calm)
8. Dark mode → imagens legíveis?

## Histórico de notas
| Rodada | Nota | Status |
|---|---|---|
| 1 | — | pending |
