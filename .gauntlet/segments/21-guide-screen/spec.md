# Segmento 21 — Guide Screen (Conteúdo Educativo)

- **Onda**: 3
- **Depende de**: 02-component-card, 01-component-button, 08-scaffold-layout
- **Escopo de arquivos**: `mobile/lib/features/guide/guide_screen.dart`

## Entregável
Guide screen redesenhada com:
- Lista de tópicos educativos (como usar o app, dicas de bem-estar, etc)
- Cada tópico tem ícone, título, descrição curta
- Clique em tópico → detail com conteúdo completo
- Conteúdo em seções com títulos e imagens
- Botão "Pular" ou "Ver Depois" no onboarding
- Opção de mostrar novamente no settings

## Critérios de aceitação
1. Lista de tópicos é clara (ícones + títulos legíveis)
2. Descrição curta é truncada (2 linhas máx)
3. Clique em tópico → detail screen com conteúdo
4. Conteúdo tem seções numeradas ou com headings
5. Imagens/ilustrações são pequenas e legíveis
6. Texto é sem jargão (leigo consegue entender)
7. Botão "Pular" é visível no onboarding
8. Dark mode funciona
9. Conteúdo não é alarmante (tom positivo)
10. Espaçamento é generoso (não aperto)

## Benchmark
Apple Tips, Figma help center. Conteúdo acessível, bem estruturado, visual claro.

## Método de verificação
- Nível: 2 (screenshot + reading)
- Ferramenta: App emulador, lê conteúdo de alguns tópicos

### Roteiro de experiência
1. Abrir app novo → guide screen aparece no onboarding?
2. Ver lista de tópicos (ícones claros? Titles legíveis?)
3. Clicar em tópico → detail com conteúdo
4. Observar: conteúdo é claro e sem jargão?
5. Voltar → lista intacta?
6. Settings → opção "mostrar guide novamente"?
7. Dark mode → texto legível?

## Histórico de notas
| Rodada | Nota | Status |
|---|---|---|
| 1 | — | pending |
