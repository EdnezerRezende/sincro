# Segmento 22 — Professionals Search (Busca de Profissionais)

- **Onda**: 3
- **Depende de**: 02-component-card, 03-component-input, 08-scaffold-layout
- **Escopo de arquivos**: `mobile/lib/features/professionals/professionals_search_screen.dart`, `mobile/lib/features/professionals/professional_detail_screen.dart`

## Entregável
Professionals search screen redesenhada com:
- Search input no topo (placeholder "Buscar profissional")
- Filtros: tipo (psicólogo, psiquiatra, etc), localização
- Grid ou lista de profissionais (foto, nome, especialidade, distância)
- Detail screen com bio, horários, contato
- Botão "Conectar" ou "Chamar" bem visível
- Empty search/filter → empty state claro

## Critérios de aceitação
1. Search input é claro (placeholder informativi, ícone lupa)
2. Filtros são acessíveis (dropdown ou chips)
3. Resultados aparecem em grid/lista bem espaçada
4. Foto profissional é legível (thumbnail decente)
5. Especialidade e distância são claros
6. Clique em card → detail screen
7. Detail tem bio, horários, botão contato
8. Empty state é claro (ex: "Nenhum profissional encontrado")
9. Dark mode funciona
10. Sem informação pessoal exposta demais (privacy-aware)

## Benchmark
Uber Drivers, Airbnb hosts, LinkedIn profiles. Claro, confível, bem estruturado.

## Método de verificação
- Nível: 2 (screenshot + mock data)
- Ferramenta: App emulador, mock lista de profissionais

### Roteiro de experiência
1. Abrir Professionals search
2. Ver filtros (tipo, localização claros?)
3. Digitar na search → resultados aparecem?
4. Tirar screenshot (grid legível? Fotos claras?)
5. Clicar em profissional → detail screen
6. Observar: bio legível? Horários claros?
7. Botão contato → funciona?
8. Dark mode → tudo legível?

## Histórico de notas
| Rodada | Nota | Status |
|---|---|---|
| 1 | — | pending |
