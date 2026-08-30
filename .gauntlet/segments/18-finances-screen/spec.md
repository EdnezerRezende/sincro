# Segmento 18 — Finances Screen (Resumo Financeiro)

- **Onda**: 3
- **Depende de**: 02-component-card, 08-scaffold-layout
- **Escopo de arquivos**: `mobile/lib/features/financas/financas_screen.dart`

## Entregável
Finances screen redesenhada com:
- Saldo total em destaque (grande, legível)
- Cards de categoria (renda, despesas, investimentos)
- Gráfico de gastos (rosca ou barras por categoria)
- Status de conexão bancária (conectado/desconectar)
- Transações recentes resumidas
- Alertas visuais (ex: limite próximo)

## Critérios de aceitação
1. Saldo total é legível e em destaque (cor primária, tamanho grande)
2. Cards de categoria têm ícones + valor + status visual
3. Gráfico de gastos é proporcional e com legenda clara
4. Cores de categorias são harmônicas (não aleatórias)
5. Status conexão bancária é claro
6. Transações recentes são resumidas (remetente, valor, data)
7. Alerta não é alarmante (cor suave, ícone informativo)
8. Dark mode funciona
9. Espaçamento entre cards é consistente
10. Sem números confusos (formato claro: R$ 1.234,56)

## Benchmark
Figma budget view, Slack analytics, Notion databases. Claro, profissional, sem ruído.

## Método de verificação
- Nível: 2 (screenshot + mock data)
- Ferramenta: App emulador, mock dados financeiros

### Roteiro de experiência
1. Abrir app, navegar para Finances tab
2. Ver saldo em destaque (claro? Tamanho bom?)
3. Tirar screenshot (gráfico legível? Cores harmônicas?)
4. Observar: categorias bem diferenciadas?
5. Scroll down → transações recentes aparecem?
6. Dark mode → tudo legível?

## Histórico de notas
| Rodada | Nota | Status |
|---|---|---|
| 1 | — | pending |
