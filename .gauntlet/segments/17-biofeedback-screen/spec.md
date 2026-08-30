# Segmento 17 — Biofeedback Screen (Métricas + Gráficos)

- **Onda**: 3
- **Depende de**: 02-component-card, 08-scaffold-layout
- **Escopo de arquivos**: `mobile/lib/features/biofeedback/biofeedback_screen.dart`

## Entregável
Biofeedback screen redesenhada com:
- Cards de métrica (heart rate, HRV, stress level)
- Gráfico visual (linha, área) mostrando tendência (últimos 7 dias)
- Status de conexão smartwatch (conectado/desconectado)
- Alerts visuais se stress alto (cor vermelha suave, ícone)
- Sugestões de grounding cards se necessário
- Espaçamento claro entre seções

## Critérios de aceitação
1. Cada métrica tem card com valor, unidade, status (bom/alerta)
2. Gráfico é legível mesmo em 375px (não minúsculo)
3. Eixos de gráfico têm labels (HR, HRV, etc)
4. Cor do gráfico combina com tema
5. Status smartwatch é claro (icon + text "Conectado" ou "Desconectar")
6. Alerta stress não é alarmante (cor suave, ícone calmo)
7. Cards de métrica são espaçados
8. Dark mode funciona (gráfico ainda legível)
9. Sugestão de grounding card aparece quando stress alto
10. Nenhuma data/hora confusa (formato claro)

## Benchmark
Health app iOS, Oura Ring app. Métricas claras, gráficos legíveis, sem ruído.

## Método de verificação
- Nível: 2 (screenshot + visual inspection)
- Ferramenta: App emulador, mock dados de biofeedback

### Roteiro de experiência
1. Abrir app, navegar para Biofeedback tab
2. Ver cards de métrica (HR, HRV, etc)
3. Tirar screenshot (gráfico legível? Cores harmônicas?)
4. Observar: status smartwatch visível?
5. Simular stress alto (mock data) → cor/alerta muda?
6. Dark mode → tudo legível?

## Histórico de notas
| Rodada | Nota | Status |
|---|---|---|
| 1 | — | pending |
