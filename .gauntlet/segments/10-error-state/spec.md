# Segmento 10 — Error State (Tela de Erro)

- **Onda**: 1
- **Depende de**: 00-design-system, 01-component-button
- **Escopo de arquivos**: `mobile/lib/core/widgets/error_widget.dart` ou similar

## Entregável
Error UI reutilizável com:
- Ícone/ilustração do erro (vermelho, desconfortável mas inteligível)
- Título claro ("Algo deu errado", "Sem conexão", etc)
- Descrição curta do problema
- Botão "Tentar Novamente" em destaque
- Sem blaming language ("você errou", "inválido")

## Critérios de aceitação
1. Título é claro e traz contexto (não genérico tipo "erro")
2. Descrição é uma frase (máx 2), sem jargão técnico
3. Ícone de erro é visível (vermelho? Ícone X?)
4. Botão retry é primário (cor, tamanho)
5. Nenhuma mensagem blame ("você fez isto", "entrada inválida")
6. Dark mode: cores legíveis
7. Ocupação de tela sensível (centrado, espaçado)
8. Se houver close/voltar, é uma segunda opção clara

## Benchmark
Erro amigável tipo Apple, GitHub, Figma. Humano, útil, sem culpa.

## Método de verificação
- Nível: 1 (screenshot + network simulation)
- Ferramenta: App emulador + devtools para simular erro

### Roteiro de experiência
1. Desligar WiFi/simular erro de rede
2. Tentar carregar tela que depende de API (ex: email list)
3. Tirar screenshot de erro
4. Observar: título é claro? Botão retry é óbvio?
5. Observar: tone é amigável (não blame)?
6. Ligar WiFi novamente
7. Clicar retry → carrega?

## Histórico de notas
| Rodada | Nota | Status |
|---|---|---|
| 1 | — | pending |
